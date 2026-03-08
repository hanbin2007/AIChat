//
//  GeminiRelayBridge.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation

struct GeminiRelayBridge {
    var session: URLSession = .shared

    func streamChat(
        relayRequest: RelayChatRequest,
        apiKey: String,
        onOpen: @escaping @Sendable () async throws -> Void,
        onEvent: @escaping @Sendable (RelayOutboundEvent) async throws -> Void
    ) async throws {
        let model = relayRequest.model?.trimmedNonEmpty ?? "gemini-3-flash-preview"

        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(makeGeminiRequest(from: relayRequest, model: model))

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayHTTPError.invalidUpstreamResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = try await readAllBytes(from: bytes)
            throw upstreamError(statusCode: httpResponse.statusCode, data: errorData)
        }

        try await onOpen()

        var emittedAnswerText = ""
        var emittedThoughtText = ""
        var finishReason: String?
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else {
                continue
            }

            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload.isEmpty == false, payload != "[DONE]" else {
                continue
            }

            guard let data = payload.data(using: .utf8),
                  let chunk = try? decoder.decode(GeminiStreamChunk.self, from: data)
            else {
                continue
            }

            let parts = extractChunkParts(from: chunk)
            if let chunkFinishReason = parts.finishReason?.trimmedNonEmpty {
                finishReason = chunkFinishReason
            }

            if let delta = normalizedDelta(chunkText: parts.thoughtText, currentText: &emittedThoughtText) {
                try await onEvent(.thoughtDelta(delta))
            }

            if let delta = normalizedDelta(chunkText: parts.answerText, currentText: &emittedAnswerText) {
                try await onEvent(.answerDelta(delta))
            }
        }

        guard let finishReason else {
            throw RelayHTTPError.internalError("Relay stream ended before Gemini sent a terminal chunk.")
        }

        try await onEvent(.done(finishReason))
    }

    private func makeGeminiRequest(from request: RelayChatRequest, model: String) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: request.systemPrompt?.trimmedNonEmpty.map {
                GeminiContent(role: nil, parts: [GeminiPart(text: $0, inlineData: nil)])
            },
            contents: request.messages.map { message in
                var parts: [GeminiPart] = []

                if let text = message.text?.trimmedNonEmpty {
                    parts.append(GeminiPart(text: text, inlineData: nil))
                }

                for attachment in message.attachments {
                    parts.append(
                        GeminiPart(
                            text: nil,
                            inlineData: GeminiInlineData(
                                mimeType: attachment.mimeType,
                                data: attachment.base64Data
                            )
                        )
                    )
                }

                return GeminiContent(
                    role: message.role.lowercased() == "assistant" ? "model" : "user",
                    parts: parts
                )
            },
            generationConfig: GeminiGenerationConfig(
                temperature: 0.65,
                topP: 0.9,
                maxOutputTokens: request.maxOutputTokens.flatMap { $0 > 0 ? $0 : nil } ?? maxOutputTokens(for: model),
                thinkingConfig: thinkingConfig(
                    model: model,
                    intensity: request.thinkingIntensity ?? "balanced",
                    includeThoughts: request.includeThoughts != false
                )
            )
        )
    }

    private func thinkingConfig(
        model: String,
        intensity: String,
        includeThoughts: Bool
    ) -> GeminiThinkingConfig? {
        let normalizedIntensity = intensity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if model.hasPrefix("gemini-3") {
            if model.hasPrefix("gemini-3.1-pro"), normalizedIntensity == "extreme" {
                return GeminiThinkingConfig(
                    thinkingLevel: nil,
                    thinkingBudget: nil,
                    includeThoughts: includeThoughts
                )
            }

            let levelByIntensity = [
                "fast": "minimal",
                "balanced": "medium",
                "deep": "high",
                "extreme": "high"
            ]

            return GeminiThinkingConfig(
                thinkingLevel: levelByIntensity[normalizedIntensity] ?? "medium",
                thinkingBudget: nil,
                includeThoughts: includeThoughts
            )
        }

        let budgetByIntensity = [
            "fast": 0,
            "balanced": 8_192,
            "deep": 24_576,
            "extreme": -1
        ]

        return GeminiThinkingConfig(
            thinkingLevel: nil,
            thinkingBudget: budgetByIntensity[normalizedIntensity] ?? 8_192,
            includeThoughts: includeThoughts
        )
    }

    private func maxOutputTokens(for model: String) -> Int {
        if model.hasPrefix("gemini-3") || model.hasPrefix("gemini-2.5") {
            return 65_536
        }

        return 8_192
    }

    private func extractChunkParts(from chunk: GeminiStreamChunk) -> (answerText: String, thoughtText: String, finishReason: String?) {
        let candidate = chunk.candidates?.first
        let parts = candidate?.content?.parts ?? []

        let answerText = parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thoughtText = parts
            .filter { $0.thought == true }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (answerText, thoughtText, candidate?.finishReason)
    }

    private func normalizedDelta(chunkText: String, currentText: inout String) -> String? {
        guard chunkText.isEmpty == false else {
            return nil
        }

        if chunkText.hasPrefix(currentText) {
            let delta = String(chunkText.dropFirst(currentText.count))
            currentText = chunkText
            return delta.isEmpty ? nil : delta
        }

        if currentText.hasPrefix(chunkText) {
            return nil
        }

        currentText += chunkText
        return chunkText
    }

    private func readAllBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func upstreamError(statusCode: Int, data: Data) -> RelayHTTPError {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let envelope = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
            return .upstream(statusCode: statusCode, message: envelope.error.message)
        }

        if let raw = String(data: data, encoding: .utf8)?.trimmedNonEmpty {
            return .upstream(statusCode: statusCode, message: raw)
        }

        return .upstream(statusCode: statusCode, message: "Gemini relay failed.")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
