//
//  TranscriptionService.swift
//  AIChat Watch App
//
//  Relay-only voice transcription. Wraps `RelayAPIClient.transcribeAudio`
//  with the same prompt assembly logic the legacy direct/relay clients
//  used (`VoiceTranscriptionPromptBuilder`).
//

import Foundation

actor TranscriptionService {
    private let api: RelayAPIClient

    init(api: RelayAPIClient) {
        self.api = api
    }

    func transcribe(
        _ audio: ChatAttachment,
        in conversation: ConversationThread,
        configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        guard audio.isAudio else { throw VoiceTranscriptionError.invalidAudio }
        let prompt = VoiceTranscriptionPromptBuilder.prompt(
            for: conversation,
            customPrompt: configuration.customPrompt,
            includesContext: configuration.includesContext,
            existingDraftText: configuration.existingDraftText,
            maxContextMessages: 8,
            maxContextCharacters: 2_400
        )
        let payload = RelayTranscribeRequest(
            model: configuration.model,
            systemPrompt: VoiceTranscriptionPromptBuilder.systemPrompt,
            prompt: prompt,
            audio: RelayStreamAttachment(
                mimeType: audio.mimeType,
                base64Data: audio.data.base64EncodedString(),
                filename: audio.filename
            )
        )
        let response = try await api.transcribeAudio(payload)
        guard let transcript = response.text.nonEmptyTrimmed else {
            throw VoiceTranscriptionError.emptyTranscript
        }
        return VoiceTranscriptionResult(text: transcript, model: response.model ?? configuration.model)
    }
}
