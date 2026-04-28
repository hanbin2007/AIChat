//
//  ConversationSortingAndComposerTests.swift
//  AIChat Watch AppTests
//
//  Recency sort ordering for the conversation list, plus draft text
//  composition rules for transcription continuation.
//

import XCTest
@testable import AIChat_Watch_App

final class ConversationSortingAndComposerTests: XCTestCase {
    func testConversationRecencySortPrefersNewestUpdatedAtThenCreatedAt() {
        let older = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "older",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let newer = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "newer",
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let tiedUpdateNewerCreate = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "tie",
            createdAt: Date(timeIntervalSince1970: 180),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let sorted = [older, newer, tiedUpdateNewerCreate]
            .sorted(by: ConversationThread.sortsByMostRecentFirst)

        XCTAssertEqual(sorted.map(\.title), ["tie", "newer", "older"])
    }

    func testDraftTextComposerAppendsChineseTranscriptWithPunctuationAwareSeparator() {
        let merged = DraftTextComposer.appended(
            existing: "帮我写一封邮件给张三",
            addition: "内容是明天下午三点开会。"
        )

        XCTAssertEqual(merged, "帮我写一封邮件给张三，内容是明天下午三点开会。")
    }

    func testDraftTextComposerKeepsEnglishContinuationInline() {
        let merged = DraftTextComposer.appended(
            existing: "Summarize the meeting",
            addition: "and call out the blockers."
        )

        XCTAssertEqual(merged, "Summarize the meeting and call out the blockers.")
    }
}
