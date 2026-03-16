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
                    var emittedAttachmentKeys: Set<String> = []
                    var latestModelResponseParts: [GeminiPartPayload]?
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
                        if let modelResponseParts = streamChunk.modelResponseParts,
                           modelResponseParts.isEmpty == false {
                            latestModelResponseParts = mergeGeminiStreamModelResponseParts(
                                previousParts: latestModelResponseParts,
                                incomingParts: modelResponseParts
                            )
                        }

                        for attachment in extractImageAttachments(from: responseEnvelope, emittedKeys: &emittedAttachmentKeys) {
                            continuation.yield(.attachment(attachment))
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

                    guard accumulatedText.nonEmptyTrimmed != nil ||
                            emittedAttachmentKeys.isEmpty == false ||
                            latestModelResponseParts?.isEmpty == false
                    else {
                        throw GeminiAPIError.emptyResponse
                    }

                    if let latestModelResponseParts, latestModelResponseParts.isEmpty == false {
                        continuation.yield(.modelResponseParts(latestModelResponseParts))
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
            systemInstruction: assembledContext.systemInstructionParts.map(GeminiContent.systemInstruction),
            contents: contextWindow(from: assembledContext.recentMessages),
            safetySettings: chatSafetySettings(),
            tools: requestTools(for: runtimeConfiguration),
            generationConfig: generationConfig(
                for: runtimeConfiguration,
                recentMessages: assembledContext.recentMessages
            )
        )
    }

    func contextWindow(from messages: [ChatMessage]) -> [GeminiContent] {
        var contents: [GeminiContent] = []

        for message in messages {
            guard let role = message.role.geminiRole else {
                continue
            }

            let parts: [GeminiPartPayload]
            if role == "model",
               let modelResponseParts = message.cleanedModelResponseParts {
                parts = modelResponseParts
            } else {
                var messageParts = message.attachments.map { attachment in
                    GeminiPartPayload(
                        text: nil,
                        inlineData: GeminiPartInlineData(
                            mimeType: attachment.mimeType,
                            data: attachment.data.base64EncodedString()
                        )
                    )
                }

                if let text = requestText(for: message) {
                    messageParts.insert(GeminiPartPayload(text: text, inlineData: nil), at: 0)
                }

                parts = messageParts
            }

            guard parts.isEmpty == false else {
                continue
            }

            if let lastIndex = contents.indices.last, contents[lastIndex].role == role {
                contents[lastIndex].parts.append(contentsOf: parts)
            } else {
                contents.append(GeminiContent(role: role, parts: parts))
            }
        }

        return contents
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
            modelResponseParts: parts.isEmpty ? nil : parts,
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

    private func generationConfig(
        for runtimeConfiguration: ConversationAIConfiguration,
        recentMessages: [ChatMessage]
    ) -> GeminiGenerationConfig {
        GeminiGenerationConfig(
            temperature: requestTemperature(for: runtimeConfiguration.model, fallback: 0.65),
            topP: 0.95,
            topK: nil,
            maxOutputTokens: AIModelCatalog.maxOutputTokens(for: runtimeConfiguration.model),
            thinkingConfig: thinkingConfiguration(for: runtimeConfiguration),
            responseMimeType: nil,
            enableEnhancedCivicAnswers: AIModelCatalog.usesThinkingLevel(model: runtimeConfiguration.model) ? true : nil,
            mediaResolution: recentMessages.contains { message in
                message.attachments.contains(where: \.isImage)
            } ? "MEDIA_RESOLUTION_HIGH" : nil
        )
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

    private func requestTools(for runtimeConfiguration: ConversationAIConfiguration) -> [GeminiTool]? {
        var tools: [GeminiTool] = []

        if runtimeConfiguration.usesGoogleSearch {
            tools.append(GeminiTool(googleSearch: GeminiGoogleSearchTool(), codeExecution: nil))
        }

        if runtimeConfiguration.usesCodeExecution {
            tools.append(GeminiTool(googleSearch: nil, codeExecution: GeminiCodeExecutionTool()))
        }

        return tools.isEmpty ? nil : tools
    }

    private func chatSafetySettings() -> [GeminiSafetySetting] {
        GeminiSafetySetting.aiStudioDefaults
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

func mergeGeminiStreamModelResponseParts(
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

func mergedGeminiText(
    from parts: [GeminiPartPayload],
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

func extractImageAttachments(
    from responseEnvelope: GeminiGenerateContentResponse,
    emittedKeys: inout Set<String>
) -> [ChatAttachment] {
    let parts = responseEnvelope.candidates
        .compactMap { $0.content?.parts }
        .first ?? []

    return parts.compactMap { part in
        guard let inlineData = part.inlineData,
              inlineData.mimeType.lowercased().hasPrefix("image/"),
              let rawData = Data(base64Encoded: inlineData.data)
        else {
            return nil
        }

        let key = geminiAttachmentKey(mimeType: inlineData.mimeType, rawData: rawData)
        guard emittedKeys.contains(key) == false else {
            return nil
        }

        guard let attachment = try? ChatAttachment.makeModelGeneratedImage(
            from: rawData,
            mimeType: inlineData.mimeType,
            suggestedFilename: "generated-image"
        ) else {
            return nil
        }

        emittedKeys.insert(key)
        return attachment
    }
}

func geminiAttachmentKey(mimeType: String, rawData: Data) -> String {
    "\(mimeType.lowercased())|\(rawData.base64EncodedString())"
}

func readAllBytes(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var collected = Data()
    for try await byte in bytes {
        collected.append(byte)
    }
    return collected
}

nonisolated struct GeminiGenerateContentRequest: Encodable, Sendable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
    var safetySettings: [GeminiSafetySetting]?
    var tools: [GeminiTool]?
    var generationConfig: GeminiGenerationConfig

    init(
        systemInstruction: GeminiContent?,
        contents: [GeminiContent],
        safetySettings: [GeminiSafetySetting]? = nil,
        tools: [GeminiTool]? = nil,
        generationConfig: GeminiGenerationConfig
    ) {
        self.systemInstruction = systemInstruction
        self.contents = contents
        self.safetySettings = safetySettings
        self.tools = tools
        self.generationConfig = generationConfig
    }
}

nonisolated struct GeminiTool: Codable, Equatable, Sendable {
    var googleSearch: GeminiGoogleSearchTool?
    var codeExecution: GeminiCodeExecutionTool?
}

nonisolated struct GeminiGoogleSearchTool: Codable, Equatable, Sendable {}

nonisolated struct GeminiCodeExecutionTool: Codable, Equatable, Sendable {}

nonisolated struct GeminiGenerationConfig: Codable, Equatable, Sendable {
    var temperature: Double
    var topP: Double
    var topK: Int?
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
    var responseMimeType: String?
    var enableEnhancedCivicAnswers: Bool?
    var mediaResolution: String?
}

nonisolated struct GeminiThinkingConfig: Codable, Equatable, Sendable {
    var thinkingBudget: Int?
    var thinkingLevel: String?
    var includeThoughts: Bool?
}

nonisolated struct GeminiSafetySetting: Codable, Equatable, Sendable {
    var category: String
    var threshold: String

    nonisolated static let aiStudioDefaults: [GeminiSafetySetting] = [
        GeminiSafetySetting(category: "HARM_CATEGORY_HARASSMENT", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_HATE_SPEECH", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "OFF")
    ]
}

nonisolated struct GeminiContent: Codable, Equatable, Sendable {
    var role: String?
    var parts: [GeminiPartPayload]

    nonisolated static func systemInstruction(_ parts: [GeminiPartPayload]) -> GeminiContent {
        GeminiContent(role: nil, parts: parts)
    }

    nonisolated static func systemPrompt(_ text: String) -> GeminiContent {
        systemInstruction([GeminiPartPayload(text: text, inlineData: nil)])
    }
}

nonisolated struct GeminiGenerateContentResponse: Decodable, Sendable {
    var candidates: [GeminiCandidate]

    private enum CodingKeys: String, CodingKey {
        case candidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.candidates = try container.decodeIfPresent([GeminiCandidate].self, forKey: .candidates) ?? []
    }
}

nonisolated struct GeminiCandidate: Decodable, Sendable {
    var content: GeminiContent?
    var finishReason: String?
}

nonisolated struct GeminiStreamChunk: Equatable, Sendable {
    var answerText: String?
    var thoughtSummary: String?
    var modelResponseParts: [GeminiPartPayload]?
    var finishReason: String?
}

nonisolated struct GeminiAPIErrorEnvelope: Decodable, Sendable {
    var error: GeminiAPIErrorMessage
}

nonisolated struct GeminiAPIErrorMessage: Decodable, Sendable {
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
