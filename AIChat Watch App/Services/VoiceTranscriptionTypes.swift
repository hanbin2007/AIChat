//
//  VoiceTranscriptionTypes.swift
//  AIChat Watch App
//
//  Shared transcription value types + the prompt builder. Extracted
//  from the deleted Gemini direct-mode service so the new
//  `TranscriptionService` (relay-only) can keep using them. The
//  prompt builder is unchanged from the legacy implementation — no
//  reason to churn behaviour the field has tested.
//

import Foundation

struct VoiceTranscriptionResult: Equatable, Sendable {
    var text: String
    var model: String
}

struct VoiceTranscriptionConfiguration: Equatable, Sendable {
    var model: String
    var customPrompt: String
    var includesContext: Bool
    var existingDraftText: String

    init(
        model: String,
        customPrompt: String = "",
        includesContext: Bool = true,
        existingDraftText: String = ""
    ) {
        self.model = model
        self.customPrompt = customPrompt
        self.includesContext = includesContext
        self.existingDraftText = existingDraftText
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
            contextSummary: includesContext
                ? AIContextAssembler.transcriptionContextSummary(for: conversation)
                : nil
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
