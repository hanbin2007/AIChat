//
//  GeminiAPIClient.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum GeminiAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case api(message: String)
    case emptyResponse
    case incompleteResponse
    case truncated

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return L10n.tr("error.gemini.missing_api_key")
        case .invalidResponse:
            return L10n.tr("error.gemini.invalid_response")
        case .api(let message):
            return message
        case .emptyResponse:
            return L10n.tr("error.gemini.empty_response")
        case .incompleteResponse:
            return L10n.tr("error.reply.incomplete")
        case .truncated:
            return L10n.tr("error.reply.truncated")
        }
    }
}

struct GeminiAPIClient: AIStreamingService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 12
    var maxCharacterBudget: Int = 12_000
    var maxInlineAttachmentBytes: Int = 4_000_000

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    guard let apiKey = configuration.geminiAPIKey else {
                        throw GeminiAPIError.missingAPIKey
                    }

                    let runtimeConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)

                    var request = URLRequest(
                        url: URL(
                            string: "https://generativelanguage.googleapis.com/v1beta/models/\(runtimeConfiguration.model):streamGenerateContent?alt=sse"
                        )!
                    )
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    request.httpBody = try encoder.encode(makeRequestBody(for: conversation))

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
                    var accumulatedThoughtSummary = ""
                    var finishReason: String?

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
                        let streamChunk = extractChunk(from: responseEnvelope)
                        if let chunkFinishReason = streamChunk.finishReason {
                            finishReason = chunkFinishReason
                        }

                        if let thoughtDelta = normalizedDelta(
                            chunkText: streamChunk.thoughtSummary ?? "",
                            currentText: &accumulatedThoughtSummary
                        ),
                        thoughtDelta.isEmpty == false {
                            continuation.yield(.thoughtDelta(thoughtDelta))
                        }

                        if let answerDelta = normalizedDelta(
                            chunkText: streamChunk.answerText ?? "",
                            currentText: &accumulatedText
                        ),
                        answerDelta.isEmpty == false {
                            continuation.yield(.answerDelta(answerDelta))
                        }
                    }

                    if let completionError = geminiCompletionError(for: finishReason) {
                        throw completionError
                    }

                    guard accumulatedText.nonEmptyTrimmed != nil else {
                        throw GeminiAPIError.emptyResponse
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }

    func makeRequestBody(for conversation: ConversationThread) -> GeminiGenerateContentRequest {
        let runtimeConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        let assembledContext = AIContextAssembler.assembleReplyContext(
            for: conversation,
            configuration: runtimeConfiguration
        )

        return GeminiGenerateContentRequest(
            systemInstruction: assembledContext.systemPrompt.map(GeminiContent.systemPrompt),
            contents: contextWindow(
                from: assembledContext.recentMessages,
                prefaceText: assembledContext.prefaceText
            ),
            generationConfig: GeminiGenerationConfig(
                temperature: requestTemperature(for: runtimeConfiguration.model, fallback: 0.65),
                topP: 0.9,
                maxOutputTokens: AIModelCatalog.maxOutputTokens(for: runtimeConfiguration.model),
                thinkingConfig: thinkingConfiguration(for: runtimeConfiguration)
            )
        )
    }

    func contextWindow(
        from messages: [ChatMessage],
        prefaceText: String?
    ) -> [GeminiContent] {
        var contents: [GeminiContent] = []

        if let prefaceText = prefaceText?.nonEmptyTrimmed {
            contents.append(
                GeminiContent(
                    role: "user",
                    parts: [GeminiPart(text: prefaceText, inlineData: nil)]
                )
            )
        }

        contents.append(contentsOf: messages.compactMap { message in
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

            if let text = requestText(for: message) {
                parts.insert(GeminiPart(text: text, inlineData: nil), at: 0)
            }

            return GeminiContent(role: role, parts: parts)
        })

        return contents
    }

    func contextWindow(from messages: [ChatMessage]) -> [GeminiContent] {
        contextWindow(from: messages, prefaceText: nil)
    }

    private func extractChunk(from responseEnvelope: GeminiGenerateContentResponse) -> GeminiStreamChunk {
        let parts = responseEnvelope.candidates
            .compactMap { $0.content?.parts }
            .first ?? []

        let answerText = mergedGeminiText(from: parts, includeThoughts: false)
        let thoughtSummary = mergedGeminiText(from: parts, includeThoughts: true)

        let finishReason = responseEnvelope.candidates
            .compactMap(\.finishReason)
            .first?
            .nonEmptyTrimmed

        return GeminiStreamChunk(
            answerText: answerText,
            thoughtSummary: thoughtSummary,
            finishReason: finishReason
        )
    }

    private func requestText(for message: ChatMessage) -> String? {
        if let text = message.cleanedText.nonEmptyTrimmed {
            return text
        }

        guard message.role == .user, message.attachments.contains(where: \.isAudio) else {
            return nil
        }

        return "Listen to the attached audio, infer the user's request, and answer it directly."
    }

    private func requestTemperature(for model: String, fallback: Double) -> Double {
        AIModelCatalog.usesThinkingLevel(model: model) ? 1 : fallback
    }

    private func thinkingConfiguration(for runtimeConfiguration: ConversationAIConfiguration) -> GeminiThinkingConfig {
        if AIModelCatalog.usesThinkingLevel(model: runtimeConfiguration.model) {
            return GeminiThinkingConfig(
                thinkingBudget: nil,
                thinkingLevel: runtimeConfiguration.thinkingIntensity.gemini3ThinkingLevel(for: runtimeConfiguration.model),
                includeThoughts: true
            )
        }

        return GeminiThinkingConfig(
            thinkingBudget: runtimeConfiguration.thinkingIntensity.gemini25ThinkingBudget,
            thinkingLevel: nil,
            includeThoughts: true
        )
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
    guard chunkText.isEmpty == false else {
        return nil
    }

    if chunkText.hasPrefix(currentText) {
        let delta = String(chunkText.dropFirst(currentText.count))
        currentText = chunkText
        return delta
    }

    if currentText.hasPrefix(chunkText) {
        return nil
    }

    currentText.append(chunkText)
    return chunkText
}

func mergedGeminiText(
    from parts: [GeminiPart],
    includeThoughts: Bool
) -> String? {
    let merged = parts.reduce(into: "") { partialResult, part in
        guard (part.thought == true) == includeThoughts, let text = part.text else {
            return
        }

        partialResult.append(text)
    }

    return merged.isEmpty ? nil : merged
}

func readAllBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var collected = Data()
    for try await byte in bytes {
        collected.append(byte)
    }
    return collected
}

struct GeminiGenerateContentRequest: Encodable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

struct GeminiGenerationConfig: Codable, Equatable {
    var temperature: Double
    var topP: Double
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
    var responseMimeType: String?
}

struct GeminiThinkingConfig: Codable, Equatable {
    var thinkingBudget: Int?
    var thinkingLevel: String?
    var includeThoughts: Bool?
}

struct GeminiContent: Codable, Equatable {
    var role: String?
    var parts: [GeminiPart]

    nonisolated static func systemPrompt(_ text: String) -> GeminiContent {
        GeminiContent(role: nil, parts: [GeminiPart(text: text, inlineData: nil)])
    }
}

struct GeminiPart: Codable, Equatable {
    var text: String?
    var inlineData: GeminiInlineData?
    var thought: Bool?

    nonisolated init(
        text: String?,
        inlineData: GeminiInlineData?,
        thought: Bool? = nil
    ) {
        self.text = text
        self.inlineData = inlineData
        self.thought = thought
    }
}

struct GeminiInlineData: Codable, Equatable {
    var mimeType: String
    var data: String
}

struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]

    private enum CodingKeys: String, CodingKey {
        case candidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidates = try container.decodeIfPresent([GeminiCandidate].self, forKey: .candidates) ?? []
    }
}

struct GeminiCandidate: Decodable {
    var content: GeminiContent?
    var finishReason: String?
}

struct GeminiStreamChunk: Equatable {
    var answerText: String?
    var thoughtSummary: String?
    var finishReason: String?
}

struct GeminiAPIErrorEnvelope: Decodable {
    var error: GeminiAPIErrorMessage
}

struct GeminiAPIErrorMessage: Decodable {
    var message: String
}

func geminiCompletionError(for finishReason: String?) -> GeminiAPIError? {
    guard let normalizedReason = finishReason?.trimmed.nonEmptyTrimmed?.uppercased() else {
        return .incompleteResponse
    }

    switch normalizedReason {
    case "STOP":
        return nil
    case "MAX_TOKENS":
        return .truncated
    default:
        return .api(message: L10n.format("error.gemini.incomplete_finish", normalizedReason))
    }
}
