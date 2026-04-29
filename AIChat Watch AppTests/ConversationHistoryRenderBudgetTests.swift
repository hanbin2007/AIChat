//
//  ConversationHistoryRenderBudgetTests.swift
//  AIChat Watch AppTests
//
//  Tests for `ConversationHistoryRenderBudget` — when the watch defers
//  initial rendering of older messages, how many to keep visible, where
//  to anchor the load-more control, etc.
//

import XCTest
@testable import AIChat_Watch_App

final class ConversationHistoryRenderBudgetTests: XCTestCase {
    func testConversationHistoryRenderBudgetDefersSmallHeavyConversation() {
        let messages = makeAlternatingMessages(
            count: 8,
            text: String(repeating: "Large content block ", count: 280)
        )

        XCTAssertTrue(
            ConversationHistoryRenderBudget.shouldDeferInitialRendering(
                in: messages,
                threshold: 48
            )
        )
        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 10
            ),
            2
        )
    }

    func testConversationHistoryRenderBudgetKeepsSmallLightConversationEager() {
        let messages = makeAlternatingMessages(
            count: 8,
            text: "Short reply"
        )

        XCTAssertFalse(
            ConversationHistoryRenderBudget.shouldDeferInitialRendering(
                in: messages,
                threshold: 48
            )
        )
        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 10
            ),
            messages.count
        )
    }

    func testConversationHistoryRenderBudgetAlwaysKeepsNewestMessageVisible() {
        let messages = makeAlternatingMessages(
            count: 1,
            text: String(repeating: "Very long answer ", count: 400)
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 1
            ),
            1
        )
    }

    func testConversationHistoryRenderBudgetAlwaysKeepsLatestExchangeVisible() {
        let messages = [
            ChatMessage(role: .user, text: "Older question"),
            ChatMessage(role: .assistant, text: "Older answer"),
            ChatMessage(role: .user, text: "Latest question"),
            ChatMessage(role: .assistant, text: String(repeating: "Very long answer ", count: 400))
        ]

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 1
            ),
            2
        )
    }

    func testConversationHistoryRenderBudgetKeepsPendingLatestUserMessageVisible() {
        let messages = [
            ChatMessage(role: .user, text: "Older question"),
            ChatMessage(role: .assistant, text: "Older answer"),
            ChatMessage(role: .user, text: String(repeating: "Latest pending request ", count: 300))
        ]

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 1
            ),
            1
        )
    }

    func testConversationHistoryRenderBudgetKeepsLoadMoreAnchorAtLastHiddenMessage() {
        let messages = makeAlternatingMessages(
            count: 5,
            text: "Short reply"
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.lastHiddenMessageID(
                in: messages,
                budget: 2
            ),
            messages[2].id
        )
    }

    func testConversationHistoryRenderBudgetLoadMoreAlwaysRevealsAnotherMessage() {
        let messages = [
            ChatMessage(role: .user, text: "Newest question"),
            ChatMessage(
                role: .assistant,
                text: Array(
                    repeating: """
                    ## 公式
                    $$\\int_0^1 x^4 dx = \\frac{1}{5}$$
                    """,
                    count: 120
                ).joined(separator: "\n")
            ),
            ChatMessage(role: .user, text: "Latest follow-up")
        ]

        let currentBudget = 1
        let nextBudget = ConversationHistoryRenderBudget.budgetForLoadingOlderMessages(
            in: messages,
            currentBudget: currentBudget,
            preferredIncrement: 1
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: currentBudget
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: nextBudget
            ),
            2
        )
    }

    private func makeAlternatingMessages(count: Int, text: String) -> [ChatMessage] {
        (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: text
            )
        }
    }
}
