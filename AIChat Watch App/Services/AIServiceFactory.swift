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

/// Errors raised by service stubs whose backend mode is no longer supported
/// in shipping builds (currently only `.direct`). The enum case
/// `AIBackendMode.direct` is retained for source compatibility with persisted
/// settings and previews, but the implementations throw this error so a
/// stray `.direct` configuration cannot reach Gemini directly with a baked-in
/// API key.
enum AIServiceError: LocalizedError {
    case directModeUnsupported

    var errorDescription: String? {
        switch self {
        case .directModeUnsupported:
            return "Direct Gemini mode is deprecated; this build only supports relay mode."
        }
    }
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
            // Direct mode is deprecated. The enum case is retained so persisted
            // settings and SwiftUI previews still decode, but the streaming
            // path has been gutted: in DEBUG we hand back the stub for tests
            // and previews; release builds trap because production must never
            // run with `.direct` selected.
            #if DEBUG
            return GeminiAPIClient(configuration: configuration)
            #else
            fatalError("Direct backend mode is no longer supported in release builds; configure AI_BACKEND_MODE = relay.")
            #endif
        case .relay:
            var client = RelayAIClient(configuration: configuration)
            client.statusHandler = relayConnectionStatusHandler
            return client
        }
    }

    static func makeTranscriptionService(configuration: AppConfiguration) -> AITranscriptionService? {
        switch configuration.backendMode {
        case .direct:
            // Deprecated; see `makeService(...)`.
            #if DEBUG
            guard configuration.geminiAPIKey != nil else {
                return nil
            }
            return GeminiTranscriptionService(configuration: configuration)
            #else
            return nil
            #endif
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
            // Deprecated; see `makeService(...)`. Fall back to the heuristic
            // extractor in DEBUG and release alike — there is no shipping
            // direct-mode path that should be calling Gemini directly.
            #if DEBUG
            guard configuration.geminiAPIKey != nil else {
                return HeuristicMemoryMaintenanceService()
            }

            return ModelBackedMemoryMaintenanceService(
                extractor: GeminiMemoryExtractionClient(configuration: configuration),
                defaultModel: configuration.geminiModel
            )
            #else
            return HeuristicMemoryMaintenanceService()
            #endif
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
