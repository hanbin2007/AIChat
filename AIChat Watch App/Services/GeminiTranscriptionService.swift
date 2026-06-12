//
//  GeminiTranscriptionService.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation

nonisolated private enum VoiceTranscriptionLimits {
    static let maxOutputTokens = 5_120
}

nonisolated enum VoiceTranscriptionPromptBuilder {
    static let systemPrompt =
        """
        You transcribe short voice prompts for AIChat on Apple devices.
        Return only the final transcript text.
        Do not answer the user.
        Use the provided conversation context only to disambiguate names, references, and homophones.
        Preserve the user's language and intent.
        Remove only obvious filler words or false starts when the intended wording is clear.
        Add obvious punctuation and capitalization when you are confident.
        """

    static func prompt(
        for conversation: ConversationThread,
        customPrompt: String,
        includesContext: Bool,
        existingDraftText: String,
        maxContextMessages: Int,
        maxContextCharacters: Int
    ) -> String {
        prompt(
            customPrompt: customPrompt,
            existingDraftText: existingDraftText,
            contextSummary: includesContext ?
                AIContextAssembler.transcriptionContextSummary(for: conversation) :
                nil
        )
    }

    static func prompt(
        customPrompt: String,
        existingDraftText: String,
        contextSummary: String?
    ) -> String {
        var prompt =
            """
            Transcribe the attached audio as the user's next chat message.
            Output only the transcript text.
            """

        if let existingDraftText = existingDraftText.nonEmptyTrimmed.map(normalizedDraftContext(_:)) {
            prompt.append(
                """

                Existing text already typed in the compose field:
                \(existingDraftText)

                Treat the new audio as a continuation of that draft unless the speaker clearly starts a new paragraph.
                Return only the new text to append, and avoid repeating words that are already present above.
                """
            )
        }

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

    private static func normalizedDraftContext(_ draftText: String) -> String {
        let normalizedDraft = draftText.collapseWhitespace().trimmed
        guard normalizedDraft.count > 320 else {
            return normalizedDraft
        }

        return String(normalizedDraft.suffix(320))
    }
}

enum VoiceTranscriptionError: LocalizedError, Equatable {
    case unavailable
    case invalidAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return L10n.tr("error.transcription.unavailable")
        case .invalidAudio:
            return L10n.tr("error.transcription.invalid_audio")
        case .emptyTranscript:
            return L10n.tr("error.transcription.empty")
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

        let prompt = VoiceTranscriptionPromptBuilder.prompt(
            for: conversation,
            customPrompt: transcriptionConfiguration.customPrompt,
            includesContext: transcriptionConfiguration.includesContext,
            existingDraftText: transcriptionConfiguration.existingDraftText,
            maxContextMessages: maxContextMessages,
            maxContextCharacters: maxContextCharacters
        )
        request.httpBody = try await makeRequestBodyData(
            prompt: prompt,
            audioAttachment: audioAttachment,
            model: transcriptionConfiguration.model
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw geminiAPIError(from: data)
        }

        return try parseTranscriptionResponse(
            data,
            requestedModel: transcriptionConfiguration.model
        )
    }

    func parseTranscriptionResponse(
        _ data: Data,
        requestedModel: String
    ) throws -> VoiceTranscriptionResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
        let finishReason = extractFinishReason(from: responseEnvelope)
        let transcript = extractTranscript(from: responseEnvelope)
            .collapseWhitespace()
            .trimmed

        if let completionError = transcriptionCompletionError(
            for: finishReason,
            hasTranscript: transcript.isEmpty == false
        ) {
            throw completionError
        }

        guard transcript.isEmpty == false else {
            throw VoiceTranscriptionError.emptyTranscript
        }

        return VoiceTranscriptionResult(
            text: transcript,
            model: requestedModel
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
        let prompt = VoiceTranscriptionPromptBuilder.prompt(
            for: conversation,
            customPrompt: transcriptionConfiguration.customPrompt,
            includesContext: transcriptionConfiguration.includesContext,
            existingDraftText: transcriptionConfiguration.existingDraftText,
            maxContextMessages: maxContextMessages,
            maxContextCharacters: maxContextCharacters
        )

        return Self.makeRequestBody(
            for: audioAttachment,
            prompt: prompt,
            model: transcriptionConfiguration.model
        )
    }

    nonisolated static func makeRequestBody(
        for audioAttachment: ChatAttachment,
        prompt: String,
        model: String
    ) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: GeminiContent.systemPrompt(VoiceTranscriptionPromptBuilder.systemPrompt),
            contents: [
                GeminiContent(
                    role: "user",
                    parts: [
                        GeminiPart(
                            text: prompt,
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
                temperature: Self.requestTemperature(for: model, fallback: 0.1),
                topP: 0.95,
                topK: nil,
                maxOutputTokens: VoiceTranscriptionLimits.maxOutputTokens,
                thinkingConfig: nil,
                responseMimeType: nil,
                enableEnhancedCivicAnswers: nil,
                mediaResolution: nil
            )
        )
    }

    func makeRequestBodyData(
        prompt: String,
        audioAttachment: ChatAttachment,
        model: String
    ) async throws -> Data {
        let attachment = audioAttachment

        return try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try encoder.encode(
                Self.makeRequestBody(
                    for: attachment,
                    prompt: prompt,
                    model: model
                )
            )
        }.value
    }

    private nonisolated static func requestTemperature(for model: String, fallback: Double) -> Double {
        model.hasPrefix("gemini-3") ? 1 : fallback
    }

    private func extractTranscript(from responseEnvelope: GeminiGenerateContentResponse) -> String {
        let parts = responseEnvelope.candidates
            .compactMap { $0.content?.parts }
            .first ?? []

        return mergedGeminiText(from: parts, includeThoughts: false) ?? ""
    }

    private func extractFinishReason(from responseEnvelope: GeminiGenerateContentResponse) -> String? {
        responseEnvelope.candidates
            .compactMap(\.finishReason)
            .first?
            .nonEmptyTrimmed
    }

    private func transcriptionCompletionError(
        for finishReason: String?,
        hasTranscript: Bool
    ) -> GeminiAPIError? {
        if finishReason?.nonEmptyTrimmed == nil, hasTranscript {
            return nil
        }

        return geminiCompletionError(for: finishReason)
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
