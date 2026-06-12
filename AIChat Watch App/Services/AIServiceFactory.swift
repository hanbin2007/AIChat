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

struct AIRuntimeServices {
    let streamingService: AIStreamingService
    let transcriptionService: AITranscriptionService?
    let memoryMaintenanceService: any AIMemoryMaintenanceService
}

enum AIServiceFactory {
    static func makeRuntimeServices(
        configuration: AppConfiguration,
        repository: ConversationRepository,
        relayConnectionStatusHandler: RelayConnectionStatusHandler? = nil
    ) -> AIRuntimeServices {
        let relayAccessRootURL = repository.resolvedRootURL
        return AIRuntimeServices(
            streamingService: makeService(
                configuration: configuration,
                relayConnectionStatusHandler: relayConnectionStatusHandler,
                relayAccessRootURL: relayAccessRootURL
            ),
            transcriptionService: makeTranscriptionService(
                configuration: configuration,
                relayAccessRootURL: relayAccessRootURL
            ),
            memoryMaintenanceService: makeMemoryMaintenanceService(
                configuration: configuration,
                relayAccessRootURL: relayAccessRootURL
            )
        )
    }

    static func makeService(
        configuration: AppConfiguration,
        relayConnectionStatusHandler: RelayConnectionStatusHandler? = nil,
        relayAccessRootURL: URL? = nil
    ) -> AIStreamingService {
        let credentialProvider = StoredRelayCredentialProvider(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        var client = RelayAIClient(
            configuration: configuration,
            relayAccessRootURL: relayAccessRootURL,
            credentialProvider: credentialProvider
        )
        client.statusHandler = relayConnectionStatusHandler
        return client
    }

    static func makeTranscriptionService(
        configuration: AppConfiguration,
        relayAccessRootURL: URL? = nil
    ) -> AITranscriptionService? {
        guard configuration.relayBaseURL != nil else {
            return nil
        }

        let credentialProvider = StoredRelayCredentialProvider(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        return RelayTranscriptionService(
            configuration: configuration,
            relayAccessRootURL: relayAccessRootURL,
            credentialProvider: credentialProvider
        )
    }

    static func makeMemoryMaintenanceService(
        configuration: AppConfiguration,
        relayAccessRootURL: URL? = nil
    ) -> any AIMemoryMaintenanceService {
        guard configuration.relayMemoryExtractURL != nil else {
            return HeuristicMemoryMaintenanceService()
        }

        let credentialProvider = StoredRelayCredentialProvider(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        return ModelBackedMemoryMaintenanceService(
            extractor: RelayMemoryExtractionClient(
                configuration: configuration,
                relayAccessRootURL: relayAccessRootURL,
                credentialProvider: credentialProvider
            ),
            defaultModel: configuration.geminiModel
        )
    }
}
