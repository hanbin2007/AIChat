//
//  ConversationHistoryController.swift
//  AIChat Watch App
//
//  Shared conversation history budget & pagination constants and helpers
//  used by both ConversationDetailView (watchOS) and
//  CompanionConversationDetailView (iOS).
//

import Foundation

enum ConversationHistoryController {

    struct Configuration {
        let prewarmedBudget: Int
        let initialBudget: Int
        let olderBudget: Int
        let deferredThreshold: Int
        let initialLoadDelayNanoseconds: UInt64

        static let watch = Configuration(
            prewarmedBudget: 10,
            initialBudget: 32,
            olderBudget: 64,
            deferredThreshold: 48,
            initialLoadDelayNanoseconds: 120_000_000
        )

        static let iOS = Configuration(
            prewarmedBudget: 10,
            initialBudget: 40,
            olderBudget: 80,
            deferredThreshold: 64,
            initialLoadDelayNanoseconds: 100_000_000
        )
    }

    static func visibleMessages(
        in conversation: ConversationThread,
        budget: Int
    ) -> [ChatMessage] {
        let messages = conversation.messages
        let count = ConversationHistoryRenderBudget.visibleMessageCount(
            in: messages,
            budget: budget
        )
        return Array(messages.suffix(count))
    }

    /// Whether the initial render should be deferred (heavy conversation).
    static func shouldDeferInitialRendering(
        messages: [ChatMessage],
        config: Configuration
    ) -> Bool {
        ConversationHistoryRenderBudget.shouldDeferInitialRendering(
            in: messages,
            threshold: config.deferredThreshold
        )
    }

    static func totalCost(for messages: [ChatMessage]) -> Int {
        ConversationHistoryRenderBudget.totalCost(in: messages)
    }

    static func budgetForLoadingOlderMessages(
        messages: [ChatMessage],
        currentBudget: Int,
        config: Configuration
    ) -> Int {
        ConversationHistoryRenderBudget.budgetForLoadingOlderMessages(
            in: messages,
            currentBudget: max(currentBudget, config.initialBudget),
            preferredIncrement: config.olderBudget
        )
    }

    static func lastHiddenMessageID(
        messages: [ChatMessage],
        budget: Int
    ) -> UUID? {
        ConversationHistoryRenderBudget.lastHiddenMessageID(
            in: messages,
            budget: budget
        )
    }
}
