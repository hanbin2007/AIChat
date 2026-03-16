//
//  GeminiRelayBridge.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation

private enum RelayTranscriptionLimits {
    static let maxOutputTokens = 5_120
}

private enum RelayMemoryExtractionLimits {
    static let maxOutputTokens = 4_096
}

struct GeminiRelayBridge {
    var session: URLSession = .shared

    func streamChat(
        relayRequest: RelayChatRequest,
        apiKey: String,
        debugLog: (@Sendable (RelayDebugEvent) async -> Void)? = nil,
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
        let requestBody = try encoder.encode(makeGeminiRequest(from: relayRequest, model: model))
        request.httpBody = requestBody

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .request,
                    title: "Gemini Request",
                    summary: "Chat stream request",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: nil,
                    body: RelayDebugFormatter.httpRequest(
                    method: request.httpMethod ?? "POST",
                    url: request.url?.absoluteString ?? "",
                    headers: request.allHTTPHeaderFields ?? [:],
                    body: requestBody
                )
                )
            )
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayHTTPError.invalidUpstreamResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorData = try await readAllBytes(from: bytes)
            if let debugLog {
                await debugLog(
                    RelayDebugEvent(
                        source: .upstream,
                        kind: .response,
                        title: "Gemini Response",
                        summary: "Chat stream error",
                        method: request.httpMethod ?? "POST",
                        path: request.url?.path,
                        address: request.url?.host,
                        statusCode: httpResponse.statusCode,
                        body: RelayDebugFormatter.httpResponse(
                        statusCode: httpResponse.statusCode,
                        headers: httpHeaders(from: httpResponse),
                        body: errorData
                    )
                    )
                )
            }
            throw upstreamError(statusCode: httpResponse.statusCode, data: errorData)
        }

        try await onOpen()

        var emittedAnswerText = ""
        var emittedThoughtText = ""
        var emittedAttachmentKeys: Set<String> = []
        var latestModelResponseParts: [GeminiPartPayload]?
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
            if let modelResponseParts = parts.modelResponseParts,
               modelResponseParts.isEmpty == false {
                latestModelResponseParts = mergeGeminiStreamModelResponseParts(
                    previousParts: latestModelResponseParts,
                    incomingParts: modelResponseParts
                )
            }

            for attachment in parts.attachments {
                let key = "\(attachment.mimeType.lowercased())|\(attachment.base64Data)"
                guard emittedAttachmentKeys.contains(key) == false else {
                    continue
                }

                emittedAttachmentKeys.insert(key)
                try await onEvent(.attachment(attachment))
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

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .response,
                    title: "Gemini Response",
                    summary: "Chat stream completed",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: httpResponse.statusCode,
                    body: RelayDebugFormatter.prettyJSON(
                    [
                        "status_code": httpResponse.statusCode,
                        "finish_reason": finishReason,
                        "answer_text": emittedAnswerText,
                        "thought_text": emittedThoughtText
                    ]
                )
                )
            )
        }

        if let latestModelResponseParts, latestModelResponseParts.isEmpty == false {
            try await onEvent(.modelResponseParts(latestModelResponseParts))
        }

        try await onEvent(.done(finishReason))
    }

    func transcribeAudio(
        relayRequest: RelayTranscriptionRequest,
        apiKey: String,
        debugLog: (@Sendable (RelayDebugEvent) async -> Void)? = nil
    ) async throws -> RelayTranscriptionResponse {
        let model = relayRequest.model?.trimmedNonEmpty ?? "gemini-3-flash-preview"

        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let requestBody = try encoder.encode(makeGeminiTranscriptionRequest(from: relayRequest, model: model))
        request.httpBody = requestBody

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .request,
                    title: "Gemini Request",
                    summary: "Transcription request",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: nil,
                    body: RelayDebugFormatter.httpRequest(
                    method: request.httpMethod ?? "POST",
                    url: request.url?.absoluteString ?? "",
                    headers: request.allHTTPHeaderFields ?? [:],
                    body: requestBody
                )
                )
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayHTTPError.invalidUpstreamResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let debugLog {
                await debugLog(
                    RelayDebugEvent(
                        source: .upstream,
                        kind: .response,
                        title: "Gemini Response",
                        summary: "Transcription error",
                        method: request.httpMethod ?? "POST",
                        path: request.url?.path,
                        address: request.url?.host,
                        statusCode: httpResponse.statusCode,
                        body: RelayDebugFormatter.httpResponse(
                        statusCode: httpResponse.statusCode,
                        headers: httpHeaders(from: httpResponse),
                        body: data
                    )
                    )
                )
            }
            throw upstreamError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responseEnvelope = try decoder.decode(GeminiStreamChunk.self, from: data)
        let transcript = extractTranscript(from: responseEnvelope)
            .collapsedWhitespace
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let completionError = transcriptionCompletionError(
            for: responseEnvelope.candidates?.first?.finishReason,
            hasTranscript: transcript.isEmpty == false
        ) {
            throw completionError
        }

        guard transcript.isEmpty == false else {
            throw RelayHTTPError.internalError("Gemini did not return a usable transcript.")
        }

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .response,
                    title: "Gemini Response",
                    summary: "Transcription response",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: httpResponse.statusCode,
                    body: RelayDebugFormatter.httpResponse(
                    statusCode: httpResponse.statusCode,
                    headers: httpHeaders(from: httpResponse),
                    body: data
                )
                )
            )
        }

        return RelayTranscriptionResponse(
            text: transcript,
            model: model
        )
    }

    func extractMemory(
        relayRequest: RelayMemoryExtractionRequest,
        apiKey: String,
        debugLog: (@Sendable (RelayDebugEvent) async -> Void)? = nil
    ) async throws -> RelayMemoryExtractionResponse {
        let model = relayRequest.model?.trimmedNonEmpty ?? "gemini-3-flash-preview"

        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let requestBody = try encoder.encode(makeGeminiMemoryRequest(from: relayRequest, model: model))
        request.httpBody = requestBody

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .request,
                    title: "Gemini Request",
                    summary: "Memory extract request",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: nil,
                    body: RelayDebugFormatter.httpRequest(
                    method: request.httpMethod ?? "POST",
                    url: request.url?.absoluteString ?? "",
                    headers: request.allHTTPHeaderFields ?? [:],
                    body: requestBody
                )
                )
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayHTTPError.invalidUpstreamResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let debugLog {
                await debugLog(
                    RelayDebugEvent(
                        source: .upstream,
                        kind: .response,
                        title: "Gemini Response",
                        summary: "Memory extract error",
                        method: request.httpMethod ?? "POST",
                        path: request.url?.path,
                        address: request.url?.host,
                        statusCode: httpResponse.statusCode,
                        body: RelayDebugFormatter.httpResponse(
                        statusCode: httpResponse.statusCode,
                        headers: httpHeaders(from: httpResponse),
                        body: data
                    )
                    )
                )
            }
            throw upstreamError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responseEnvelope = try decoder.decode(GeminiStreamChunk.self, from: data)
        let responseText = extractTranscript(from: responseEnvelope)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let completionError = transcriptionCompletionError(
            for: responseEnvelope.candidates?.first?.finishReason,
            hasTranscript: responseText.isEmpty == false
        ) {
            throw completionError
        }

        let extractionResponse = try decodeMemoryExtractionResponse(from: responseText)

        if let debugLog {
            await debugLog(
                RelayDebugEvent(
                    source: .upstream,
                    kind: .response,
                    title: "Gemini Response",
                    summary: "Memory extract response",
                    method: request.httpMethod ?? "POST",
                    path: request.url?.path,
                    address: request.url?.host,
                    statusCode: httpResponse.statusCode,
                    body: RelayDebugFormatter.prettyJSON(extractionResponse)
                )
            )
        }

        return extractionResponse
    }

    private func makeGeminiRequest(from request: RelayChatRequest, model: String) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: request.systemPrompt?.trimmedNonEmpty.map {
                GeminiContent(role: nil, parts: [GeminiPartPayload(text: $0, inlineData: nil)])
            },
            contents: request.messages.map { message in
                if message.role.lowercased() == "assistant",
                   let modelResponseParts = message.modelResponseParts,
                   modelResponseParts.isEmpty == false {
                    return GeminiContent(role: "model", parts: modelResponseParts)
                }

                var parts: [GeminiPartPayload] = []

                if let text = message.text?.trimmedNonEmpty {
                    parts.append(GeminiPartPayload(text: text, inlineData: nil))
                }

                for attachment in message.attachments {
                    parts.append(
                        GeminiPartPayload(
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
            tools: requestTools(for: request),
            generationConfig: GeminiGenerationConfig(
                temperature: temperature(for: model, fallback: 0.65),
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

    private func requestTools(for request: RelayChatRequest) -> [GeminiTool]? {
        var tools: [GeminiTool] = []

        if request.usesGoogleSearch == true {
            tools.append(GeminiTool(googleSearch: GeminiGoogleSearchTool(), codeExecution: nil))
        }

        if request.usesCodeExecution == true {
            tools.append(GeminiTool(googleSearch: nil, codeExecution: GeminiCodeExecutionTool()))
        }

        return tools.isEmpty ? nil : tools
    }

    private func makeGeminiTranscriptionRequest(
        from request: RelayTranscriptionRequest,
        model: String
    ) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: request.systemPrompt?.trimmedNonEmpty.map {
                GeminiContent(role: nil, parts: [GeminiPartPayload(text: $0, inlineData: nil)])
            },
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [
                        GeminiPartPayload(text: request.prompt, inlineData: nil),
                        GeminiPartPayload(
                            text: nil,
                            inlineData: GeminiInlineData(
                                mimeType: request.audio.mimeType,
                                data: request.audio.base64Data
                            )
                        )
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: temperature(for: model, fallback: 0.1),
                topP: 0.95,
                maxOutputTokens: RelayTranscriptionLimits.maxOutputTokens,
                thinkingConfig: nil,
                responseMimeType: nil
            )
        )
    }

    private func makeGeminiMemoryRequest(
        from request: RelayMemoryExtractionRequest,
        model: String
    ) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(
                role: nil,
                parts: [
                    GeminiPartPayload(
                        text: memoryExtractionSystemPrompt,
                        inlineData: nil
                    )
                ]
            ),
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [
                        GeminiPartPayload(
                            text: memoryExtractionPrompt(for: request),
                            inlineData: nil
                        )
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: temperature(for: model, fallback: 0.1),
                topP: 0.9,
                maxOutputTokens: RelayMemoryExtractionLimits.maxOutputTokens,
                thinkingConfig: nil,
                responseMimeType: "application/json"
            )
        )
    }

    private func temperature(for model: String, fallback: Double) -> Double {
        model.hasPrefix("gemini-3") ? 1 : fallback
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

    private func extractChunkParts(from chunk: GeminiStreamChunk) -> (
        answerText: String,
        thoughtText: String,
        modelResponseParts: [GeminiPartPayload]?,
        attachments: [RelayAttachment],
        finishReason: String?
    ) {
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

        let attachments: [RelayAttachment] = parts.compactMap { part in
            guard let inlineData = part.inlineData,
                  inlineData.mimeType.lowercased().hasPrefix("image/")
            else {
                return nil
            }

            return RelayAttachment(
                mimeType: inlineData.mimeType,
                base64Data: inlineData.data,
                filename: "generated-image"
            )
        }

        return (
            answerText,
            thoughtText,
            parts.isEmpty ? nil : parts,
            attachments,
            candidate?.finishReason
        )
    }

    private func extractTranscript(from response: GeminiStreamChunk) -> String {
        let parts = response.candidates?.first?.content?.parts ?? []

        return parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    private func decodeMemoryExtractionResponse(from text: String) throws -> RelayMemoryExtractionResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let data = trimmed.data(using: .utf8),
           let response = try? decoder.decode(RelayMemoryExtractionResponse.self, from: data) {
            return response
        }

        if let range = trimmed.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
           let data = String(trimmed[range]).data(using: .utf8) {
            return try decoder.decode(RelayMemoryExtractionResponse.self, from: data)
        }

        throw RelayHTTPError.invalidUpstreamResponse
    }

    private func mergeGeminiStreamModelResponseParts(
        previousParts: [GeminiPartPayload]?,
        incomingParts: [GeminiPartPayload]
    ) -> [GeminiPartPayload] {
        guard incomingParts.isEmpty == false else {
            return previousParts ?? []
        }

        if incomingParts.contains(where: \.hasNonSignaturePayload) {
            return incomingParts
        }

        var mergedParts = previousParts ?? []
        for part in incomingParts where mergedParts.contains(part) == false {
            mergedParts.append(part)
        }

        return mergedParts
    }

    private func transcriptionCompletionError(
        for finishReason: String?,
        hasTranscript: Bool
    ) -> RelayHTTPError? {
        guard let normalizedReason = finishReason?.trimmedNonEmpty?.uppercased() else {
            if hasTranscript {
                return nil
            }
            return .internalError("Relay transcription ended before Gemini returned a terminal result.")
        }

        switch normalizedReason {
        case "STOP":
            return nil
        case "MAX_TOKENS":
            return .internalError("Transcript hit the output limit before completion.")
        default:
            return .internalError("Relay transcription reported an incomplete finish (\(normalizedReason)).")
        }
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

    private func httpHeaders(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            guard let key = pair.key as? String else {
                return
            }

            partialResult[key] = String(describing: pair.value)
        }
    }
}

private let memoryExtractionSystemPrompt =
    """
    You maintain compressed conversation memory for AIChat.
    Return strict JSON only. Do not answer the user.
    Prefer concise Chinese phrasing when the source conversation is Chinese.
    Use this schema exactly:
    {
      "kind": "casual|teaching|task",
      "title": "short title",
      "focusNote": "compact focus note",
      "openLoops": ["pending question or next step"],
      "memoryItems": ["stable reusable memory item"],
      "archiveTitle": "short archive title or null",
      "archiveSummary": "archive summary or null",
      "archiveOpenLoops": ["pending loop from archive"]
    }
    Rules:
    - Return valid JSON with double quotes and no markdown fence.
    - memoryItems must contain only stable reusable memory, not ephemeral chatter.
    - If there is no archive candidate, set archiveTitle and archiveSummary to null and archiveOpenLoops to [].
    """

private func memoryExtractionPrompt(for request: RelayMemoryExtractionRequest) -> String {
    var sections = [
        "Mode hint: \(request.mode)",
        "Conversation title: \(request.conversationTitle)"
    ]

    if let existingFocusState = request.existingFocusState {
        var focusLines: [String] = []
        if let kind = existingFocusState.kind?.trimmedNonEmpty {
            focusLines.append("kind: \(kind)")
        }
        if let title = existingFocusState.title?.trimmedNonEmpty {
            focusLines.append("title: \(title)")
        }
        if let focusNote = existingFocusState.focusNote?.trimmedNonEmpty {
            focusLines.append("focusNote: \(focusNote)")
        }
        if existingFocusState.openLoops.isEmpty == false {
            focusLines.append("openLoops: \(existingFocusState.openLoops.joined(separator: " | "))")
        }

        if focusLines.isEmpty == false {
            sections.append("Existing focus state:\n\(focusLines.joined(separator: "\n"))")
        }
    }

    if request.existingMemoryItems.isEmpty == false {
        sections.append(
            "Existing reusable memory:\n" +
            request.existingMemoryItems.map { "- \($0)" }.joined(separator: "\n")
        )
    }

    sections.append(
        "Recent messages (newest last):\n" +
        request.recentMessages.enumerated().map { index, message in
            "[\(index + 1)] \(message.role): \(message.text)"
        }.joined(separator: "\n")
    )

    if request.archiveCandidateMessages.isEmpty == false {
        sections.append(
            "Archive candidate (older stable slice to compress if useful):\n" +
            request.archiveCandidateMessages.enumerated().map { index, message in
                "[\(index + 1)] \(message.role): \(message.text)"
            }.joined(separator: "\n")
        )
    } else {
        sections.append("Archive candidate: none")
    }

    sections.append("Return JSON only.")
    return sections.joined(separator: "\n\n")
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var collapsedWhitespace: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
