//
//  ConversationAutoScrollControllerTests.swift
//  AIChat Watch AppTests
//
//  Pins the §1.2 auto-scroll state machine.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class ConversationAutoScrollControllerTests: XCTestCase {

    func test_initialState() async throws {
        let controller = ConversationAutoScrollController()
        XCTAssertNil(controller.anchorMessageID)
        XCTAssertTrue(controller.shouldFollow)
    }

    func test_messageUpdateMovesAnchor_whenFollowing() async throws {
        let controller = ConversationAutoScrollController()
        let id = UUID()

        controller.messageContentDidUpdate(latestMessageID: id)
        XCTAssertEqual(controller.anchorMessageID, id)
        XCTAssertTrue(controller.shouldFollow)

        // Same id, different "tick" — should re-publish.
        controller.messageContentDidUpdate(latestMessageID: id)
        XCTAssertEqual(controller.anchorMessageID, id)
    }

    func test_messageUpdateIgnored_whenUserScrolled() async throws {
        let controller = ConversationAutoScrollController()
        let firstID = UUID()
        controller.messageContentDidUpdate(latestMessageID: firstID)
        controller.userDidInteractWithScroll()
        XCTAssertFalse(controller.shouldFollow)

        // Anchor stays put for further updates to the same message id.
        let anchorBefore = controller.anchorMessageID
        controller.messageContentDidUpdate(latestMessageID: firstID)
        XCTAssertEqual(controller.anchorMessageID, anchorBefore)
        XCTAssertFalse(controller.shouldFollow)
    }

    func test_newMessageForcesAnchorEvenWhenFrozen() async throws {
        let controller = ConversationAutoScrollController()
        let firstID = UUID()
        let secondID = UUID()

        controller.messageContentDidUpdate(latestMessageID: firstID)
        controller.userDidInteractWithScroll()
        XCTAssertFalse(controller.shouldFollow)

        controller.messageContentDidUpdate(latestMessageID: secondID)
        XCTAssertEqual(controller.anchorMessageID, secondID)
        XCTAssertTrue(controller.shouldFollow)
    }

    func test_streamFinishReArmsFollow() async throws {
        let controller = ConversationAutoScrollController()
        controller.messageContentDidUpdate(latestMessageID: UUID())
        controller.userDidInteractWithScroll()
        XCTAssertFalse(controller.shouldFollow)

        controller.streamDidFinish()
        XCTAssertTrue(controller.shouldFollow)
    }

    func test_resetForNewConversationClearsAllState() async throws {
        let controller = ConversationAutoScrollController()
        controller.messageContentDidUpdate(latestMessageID: UUID())
        controller.userDidInteractWithScroll()

        controller.resetForNewConversation()
        XCTAssertNil(controller.anchorMessageID)
        XCTAssertTrue(controller.shouldFollow)
    }
}
