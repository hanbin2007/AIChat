//
//  PureFunctionUtilityTests.swift
//  AIChat Watch AppTests
//
//  Pure-function tests for tiny utilities (title generation, deep-link
//  parsing, completion feedback presentation rules).
//

import XCTest
@testable import AIChat_Watch_App

final class PureFunctionUtilityTests: XCTestCase {
    func testSuggestedTitleUsesCollapsedWhitespaceAndTruncates() {
        let input = "  Build   a production ready Apple Watch assistant with photo upload   "
        let title = ConversationThread.suggestedTitle(from: input)

        XCTAssertEqual(title, "Build a production ready A...")
    }

    func testAIChatDeepLinkParsesActivationImport() {
        let url = URL(string: "aichat://activation/import?code=abcd-1234-efgh")!

        XCTAssertEqual(
            AIChatDeepLink(url),
            .activationImport("ABCD-1234-EFGH")
        )
    }

    func testAIChatDeepLinkParsesNewConversation() {
        let url = URL(string: "aichat://conversation/new")!

        XCTAssertEqual(AIChatDeepLink(url), .newConversation)
    }

    func testCompletionFeedbackForegroundPresentationOptionsEnableSound() {
        let options = CompletionFeedbackEvent.foregroundPresentationOptions(
            forNotificationIdentifier: CompletionFeedbackEvent.transcriptionCompleted.notificationIdentifier
        )

        XCTAssertTrue(options.contains(.sound))
    }

    func testCompletionFeedbackForegroundPresentationOptionsIgnoreUnknownNotifications() {
        let options = CompletionFeedbackEvent.foregroundPresentationOptions(
            forNotificationIdentifier: "some-other-notification"
        )

        XCTAssertEqual(options, [])
    }
}
