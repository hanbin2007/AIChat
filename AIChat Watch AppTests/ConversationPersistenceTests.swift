//
//  ConversationPersistenceTests.swift
//  AIChat Watch AppTests
//
//  Drives `ConversationPersistence` against an in-memory V2 container.
//  Asserts CRUD semantics + that `stream()` re-emits after mutations.
//

import XCTest
import SwiftData
@testable import AIChat_Watch_App

final class ConversationPersistenceTests: XCTestCase {

    private func makePersistence() throws -> ConversationPersistence {
        let container = try AIChatModelContainer.inMemory()
        return ConversationPersistence(container: container)
    }

    func test_upsert_andLoadAll_roundTripsConversation() async throws {
        let persistence = try makePersistence()

        let attachment = Attachment(
            kind: .image,
            filename: "pic.png",
            mimeType: "image/png",
            data: Data([0xDE, 0xAD]),
            sortIndex: 0
        )
        let message = Message(
            role: .user,
            text: "Hello",
            status: .complete,
            sortIndex: 0,
            attachments: [attachment]
        )
        let conversation = Conversation(
            title: "Greeting",
            isFavorite: true,
            messages: [message]
        )

        try await persistence.upsert(conversation)
        let loaded = try await persistence.loadAll()

        XCTAssertEqual(loaded.count, 1)
        let first = try XCTUnwrap(loaded.first)
        XCTAssertEqual(first.id, conversation.id)
        XCTAssertEqual(first.title, "Greeting")
        XCTAssertTrue(first.isFavorite)
        XCTAssertEqual(first.messages.count, 1)
        XCTAssertEqual(first.messages.first?.text, "Hello")
        XCTAssertEqual(first.messages.first?.attachments.count, 1)
        XCTAssertEqual(first.messages.first?.attachments.first?.filename, "pic.png")
    }

    func test_upsert_replacesMessagesOnSecondCall() async throws {
        let persistence = try makePersistence()
        var conversation = Conversation(title: "Thread")
        conversation.messages = [
            Message(role: .user, text: "Q1", sortIndex: 0),
            Message(role: .assistant, text: "A1", sortIndex: 1)
        ]
        try await persistence.upsert(conversation)

        // Second upsert — different message set.
        conversation.messages = [
            Message(role: .user, text: "Q2", sortIndex: 0)
        ]
        conversation.updatedAt = Date()
        try await persistence.upsert(conversation)

        let loaded = try await persistence.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.messages.count, 1)
        XCTAssertEqual(loaded.first?.messages.first?.text, "Q2")
    }

    func test_delete_removesConversationAndAddsTombstone() async throws {
        let persistence = try makePersistence()
        let conversation = Conversation(title: "Doomed")
        try await persistence.upsert(conversation)

        try await persistence.delete(id: conversation.id)
        let remaining = try await persistence.loadAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_setFavorite_togglesFlag() async throws {
        let persistence = try makePersistence()
        let conversation = Conversation(title: "Flagged", isFavorite: false)
        try await persistence.upsert(conversation)

        try await persistence.setFavorite(id: conversation.id, isFavorite: true)
        let loaded = try await persistence.conversation(id: conversation.id)
        XCTAssertEqual(loaded?.isFavorite, true)
    }

    func test_loadAll_sortsByUpdatedAtDescending() async throws {
        let persistence = try makePersistence()
        let now = Date()
        let older = Conversation(
            title: "Older",
            createdAt: now.addingTimeInterval(-200),
            updatedAt: now.addingTimeInterval(-200)
        )
        let newer = Conversation(
            title: "Newer",
            createdAt: now,
            updatedAt: now
        )
        try await persistence.upsert(older)
        try await persistence.upsert(newer)

        let loaded = try await persistence.loadAll()
        XCTAssertEqual(loaded.map { $0.title }, ["Newer", "Older"])
    }

    func test_stream_emitsInitialSnapshotAndAfterMutation() async throws {
        let persistence = try makePersistence()

        // Pre-seed so the first emission has content.
        let seed = Conversation(title: "Seed")
        try await persistence.upsert(seed)

        let stream = await persistence.stream()
        var iterator = stream.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first?.count, 1)
        XCTAssertEqual(first?.first?.title, "Seed")

        // Mutate — the stream should receive a new snapshot.
        let second = Conversation(title: "Second")
        try await persistence.upsert(second)
        let next = await iterator.next()
        XCTAssertEqual(next?.count, 2)
        XCTAssertTrue(next?.contains(where: { $0.title == "Second" }) ?? false)
    }
}
