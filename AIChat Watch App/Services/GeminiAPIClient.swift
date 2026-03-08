//
//  GeminiAPIClient.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum GeminiAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case api(message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is missing."
        case .invalidResponse:
            return "Gemini returned an invalid response."
        case .api(let message):
            return message
        case .emptyResponse:
            return "Gemini returned an empty reply."
        }
    }
}

struct GeminiAPIClient: AIStreamingService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 12
    var maxCharacterBudget: Int = 12_000
    var maxInlineImageBytes: Int = 1_800_000

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let apiKey = configuration.geminiAPIKey else {
                        throw GeminiAPIError.missingAPIKey
                    }

                    var request = URLRequest(
                        url: URL(
                            string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.geminiModel):streamGenerateContent?alt=sse"
                        )!
                    )
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    request.httpBody = try encoder.encode(makeRequestBody(for: conversation.messages))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw GeminiAPIError.invalidResponse
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let errorData = try await readAllBytes(from: bytes)
                        throw geminiError(from: errorData)
                    }

                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    var accumulatedText = ""

                    for try await line in bytes.lines {
                        let trimmedLine = line.trimmed
                        guard trimmedLine.hasPrefix("data:") else {
                            continue
                        }

                        let payload = String(trimmedLine.dropFirst(5)).trimmed
                        guard payload.isEmpty == false, payload != "[DONE]" else {
                            continue
                        }

                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }

                        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
                        let chunkText = extractText(from: responseEnvelope) ?? ""
                        let delta = normalizedDelta(chunkText: chunkText, currentText: &accumulatedText)

                        if let delta, delta.isEmpty == false {
                            continuation.yield(delta)
                        }
                    }

                    guard accumulatedText.nonEmptyTrimmed != nil else {
                        throw GeminiAPIError.emptyResponse
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func makeRequestBody(for messages: [ChatMessage]) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: GeminiContent.systemPrompt(AIContextBuilder.systemPrompt),
            contents: contextWindow(from: messages),
            generationConfig: GeminiGenerationConfig(
                temperature: 0.65,
                topP: 0.9,
                maxOutputTokens: 512
            )
        )
    }

    func contextWindow(from messages: [ChatMessage]) -> [GeminiContent] {
        let selectedMessages = AIContextBuilder.selectedMessages(
            from: messages,
            maxContextMessages: maxContextMessages,
            maxCharacterBudget: maxCharacterBudget,
            maxInlineImageBytes: maxInlineImageBytes
        )

        return selectedMessages.compactMap { message in
            guard let role = message.role.geminiRole else {
                return nil
            }

            var parts = message.attachments.map { attachment in
                GeminiPart(
                    text: nil,
                    inlineData: GeminiInlineData(
                        mimeType: attachment.mimeType,
                        data: attachment.data.base64EncodedString()
                    )
                )
            }

            if let text = message.cleanedText.nonEmptyTrimmed {
                parts.insert(GeminiPart(text: text, inlineData: nil), at: 0)
            }

            return GeminiContent(role: role, parts: parts)
        }
    }

    private func extractText(from responseEnvelope: GeminiGenerateContentResponse) -> String? {
        responseEnvelope.candidates
            .compactMap { candidate in
                candidate.content?.parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .nonEmptyTrimmed
            }
            .first
    }

    private func geminiError(from data: Data) -> Error {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let apiError = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
            return GeminiAPIError.api(message: apiError.error.message)
        }

        return GeminiAPIError.invalidResponse
    }
}

func normalizedDelta(chunkText: String, currentText: inout String) -> String? {
    let normalizedChunk = chunkText.nonEmptyTrimmed
    guard let normalizedChunk else {
        return nil
    }

    if normalizedChunk.hasPrefix(currentText) {
        let delta = String(normalizedChunk.dropFirst(currentText.count))
        currentText = normalizedChunk
        return delta
    }

    if currentText.hasPrefix(normalizedChunk) {
        return nil
    }

    currentText.append(normalizedChunk)
    return normalizedChunk
}

func readAllBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var collected = Data()
    for try await byte in bytes {
        collected.append(byte)
    }
    return collected
}

struct GeminiGenerateContentRequest: Encodable {
    var systemInstruction: GeminiContent
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

struct GeminiGenerationConfig: Codable, Equatable {
    var temperature: Double
    var topP: Double
    var maxOutputTokens: Int
}

struct GeminiContent: Codable, Equatable {
    var role: String?
    var parts: [GeminiPart]

    static func systemPrompt(_ text: String) -> GeminiContent {
        GeminiContent(role: nil, parts: [GeminiPart(text: text, inlineData: nil)])
    }
}

struct GeminiPart: Codable, Equatable {
    var text: String?
    var inlineData: GeminiInlineData?
}

struct GeminiInlineData: Codable, Equatable {
    var mimeType: String
    var data: String
}

struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]
}

struct GeminiCandidate: Decodable {
    var content: GeminiContent?
}

struct GeminiAPIErrorEnvelope: Decodable {
    var error: GeminiAPIErrorMessage
}

struct GeminiAPIErrorMessage: Decodable {
    var message: String
}
