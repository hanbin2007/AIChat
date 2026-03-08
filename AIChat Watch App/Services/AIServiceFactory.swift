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

protocol AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error>
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
}
