//
//  GeminiTranscriptionService.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation

enum VoiceTranscriptionPromptBuilder {
    static let systemPrompt =
        """
        You transcribe short voice prompts for AIChat on Apple devices.
        Return only the final transcript text.
        Do not answer the user.
        Use the provided conversation context only to disambiguate names, references, and homophones.
        Preserve the user's language and intent.
        Remove only obvious filler words or false starts when the intended wording is clear.
        """

    static func prompt(
        for conversation: ConversationThread,
        customPrompt: String,
        includesContext: Bool,
        maxContextMessages: Int,
        maxContextCharacters: Int
    ) -> String {
        prompt(
            customPrompt: customPrompt,
            contextSummary: includesContext ?
                AIContextBuilder.transcriptionContextSummary(
                    from: conversation.messages,
                    maxContextMessages: maxContextMessages,
                    maxCharacterBudget: maxContextCharacters
                ) :
                nil
        )
    }

    static func prompt(
        customPrompt: String,
        contextSummary: String?
    ) -> String {
        var prompt =
            """
            Transcribe the attached audio as the user's next chat message.
            Output only the transcript text.
            """

        if let customPrompt = customPrompt.nonEmptyTrimmed {
            prompt.append(
                """

                Extra transcription instructions:
                \(customPrompt)
                """
            )
        }

        if let contextSummary {
            prompt.append(
                """

                Recent conversation context:
                \(contextSummary)
                """
            )
        }

        return prompt
    }
}

enum VoiceTranscriptionError: LocalizedError, Equatable {
    case unavailable
    case invalidAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Voice transcription is unavailable in the current configuration."
        case .invalidAudio:
            return "The recorded audio could not be prepared for transcription."
        case .emptyTranscript:
            return "Gemini did not return a usable transcript."
        }
    }
}

struct GeminiTranscriptionService: AITranscriptionService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 8
    var maxContextCharacters: Int = 2_400

    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using transcriptionConfiguration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        guard audioAttachment.isAudio else {
            throw VoiceTranscriptionError.invalidAudio
        }

        guard let apiKey = configuration.geminiAPIKey else {
            throw GeminiAPIError.missingAPIKey
        }

        var request = URLRequest(url: requestURL(for: transcriptionConfiguration.model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            makeRequestBody(
                for: audioAttachment,
                in: conversation,
                using: transcriptionConfiguration
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw geminiAPIError(from: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
        if let completionError = geminiCompletionError(for: extractFinishReason(from: responseEnvelope)) {
            throw completionError
        }

        let transcript = extractTranscript(from: responseEnvelope)
            .collapseWhitespace()
            .trimmed

        guard transcript.isEmpty == false else {
            throw VoiceTranscriptionError.emptyTranscript
        }

        return VoiceTranscriptionResult(
            text: transcript,
            model: transcriptionConfiguration.model
        )
    }

    func requestURL(for model: String) -> URL {
        URL(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        )!
    }

    func makeRequestBody(
        for audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using transcriptionConfiguration: VoiceTranscriptionConfiguration
    ) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: GeminiContent.systemPrompt(VoiceTranscriptionPromptBuilder.systemPrompt),
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [
                        GeminiPart(
                            text: VoiceTranscriptionPromptBuilder.prompt(
                                for: conversation,
                                customPrompt: transcriptionConfiguration.customPrompt,
                                includesContext: transcriptionConfiguration.includesContext,
                                maxContextMessages: maxContextMessages,
                                maxContextCharacters: maxContextCharacters
                            ),
                            inlineData: nil
                        ),
                        GeminiPart(
                            text: nil,
                            inlineData: GeminiInlineData(
                                mimeType: audioAttachment.mimeType,
                                data: audioAttachment.data.base64EncodedString()
                            )
                        )
                    ]
                )
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.1,
                topP: 0.95,
                maxOutputTokens: 1_024,
                thinkingConfig: nil
            )
        )
    }

    private func extractTranscript(from responseEnvelope: GeminiGenerateContentResponse) -> String {
        responseEnvelope.candidates
            .compactMap { $0.content?.parts }
            .first?
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }

    private func extractFinishReason(from responseEnvelope: GeminiGenerateContentResponse) -> String? {
        responseEnvelope.candidates
            .compactMap(\.finishReason)
            .first?
            .nonEmptyTrimmed
    }

    private func geminiAPIError(from data: Data) -> Error {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let apiError = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
            return GeminiAPIError.api(message: apiError.error.message)
        }

        return GeminiAPIError.invalidResponse
    }
}
