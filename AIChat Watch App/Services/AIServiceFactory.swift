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
}

struct VoiceTranscriptionResult: Equatable {
    var text: String
    var model: String
}

struct VoiceTranscriptionConfiguration: Equatable {
    var model: String
    var customPrompt: String
    var includesContext: Bool

    init(
        model: String,
        customPrompt: String = "",
        includesContext: Bool = true
    ) {
        self.model = model
        self.customPrompt = customPrompt
        self.includesContext = includesContext
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
    static func makeService(configuration: AppConfiguration) -> AIStreamingService {
        switch configuration.backendMode {
        case .direct:
            return GeminiAPIClient(configuration: configuration)
        case .relay:
            return RelayAIClient(configuration: configuration)
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
            guard configuration.relayBaseURL != nil,
                  configuration.relayBearerToken != nil
            else {
                return nil
            }

            return RelayTranscriptionService(configuration: configuration)
        }
    }
}
