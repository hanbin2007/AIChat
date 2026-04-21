//
//  AIServiceFactory.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum AIStreamEvent: Equatable {
    case answerDelta(String)
    case thoughtDelta(String)
    case attachment(ChatAttachment)
    case modelResponseParts([GeminiPartPayload])
}

struct VoiceTranscriptionResult: Equatable {
    var text: String
    var model: String
}

struct VoiceTranscriptionConfiguration: Equatable {
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

protocol AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error>
}

protocol AITranscriptionService {
    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult
}

enum AIServiceFactory {
    static func makeService(
        configuration: AppConfiguration,
        relayConnectionStatusHandler: RelayConnectionStatusHandler? = nil
    ) -> AIStreamingService {
        switch configuration.backendMode {
        case .direct:
            // Direct mode never observes or emits relay connection
            // status — the handler is ignored on this path by design.
            return GeminiAPIClient(configuration: configuration)
        case .relay:
            var client = RelayAIClient(configuration: configuration)
            client.statusHandler = relayConnectionStatusHandler
            return client
        }
    }

    static func makeTranscriptionService(configuration: AppConfiguration) -> AITranscriptionService? {
        switch configuration.backendMode {
        case .direct:
            guard configuration.geminiAPIKey != nil else {
                return nil
            }

            return GeminiTranscriptionService(configuration: configuration)
        case .relay:
            guard configuration.relayBaseURL != nil else {
                return nil
            }

            return RelayTranscriptionService(configuration: configuration)
        }
    }

    static func makeMemoryMaintenanceService(configuration: AppConfiguration) -> any AIMemoryMaintenanceService {
        switch configuration.backendMode {
        case .direct:
            guard configuration.geminiAPIKey != nil else {
                return HeuristicMemoryMaintenanceService()
            }

            return ModelBackedMemoryMaintenanceService(
                extractor: GeminiMemoryExtractionClient(configuration: configuration),
                defaultModel: configuration.geminiModel
            )
        case .relay:
            guard configuration.relayMemoryExtractURL != nil else {
                return HeuristicMemoryMaintenanceService()
            }

            return ModelBackedMemoryMaintenanceService(
                extractor: RelayMemoryExtractionClient(configuration: configuration),
                defaultModel: configuration.geminiModel
            )
        }
    }
}
