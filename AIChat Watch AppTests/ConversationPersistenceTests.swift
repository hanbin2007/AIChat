//
//  ConversationPersistenceTests.swift
//  AIChat Watch AppTests
//
//  Drives `ConversationPersistence` against an in-memory V2 container
//  using the canonical `ConversationThread` round-trip. Asserts CRUD
//  semantics + that `stream()` re-emits after mutations.
//

import XCTest
import SwiftData
@testable import AIChat_Watch_App

final class ConversationPersistenceTests: XCTestCase {

    private func makePersistence() throws -> ConversationPersistence {
        let container = try AIChatModelContainer.inMemory()
        return ConversationPersistence(container: container)
    }

    func test_upsert_andLoadAll_roundTripsConversationThread() async throws {
        let persistence = try makePersistence()

        let attachment = ChatAttachment(
            kind: .image,
            filename: "pic.png",
            mimeType: "image/png",
            data: Data([0xDE, 0xAD]),
            pixelWidth: 100,
            pixelHeight: 50
        )
        let userMessage = ChatMessage(
            role: .user,
            text: "Hello",
            attachments: [attachment],
            status: .sent
        )
        let assistantMessage = ChatMessage(
            role: .assistant,
            text: "Hi",
            status: .sent
        )
        let thread = ConversationThread(
            title: "Greeting",
            isFavorite: true,
            messages: [userMessage, assistantMessage]
        )

        try await persistence.upsert(thread)
        let loaded = try await persistence.loadAll()

        XCTAssertEqual(loaded.count, 1)
        let first = try XCTUnwrap(loaded.first)
        XCTAssertEqual(first.id, thread.id)
        XCTAssertEqual(first.title, "Greeting")
        XCTAssertTrue(first.isFavorite)
        XCTAssertEqual(first.messages.count, 2)
        XCTAssertEqual(first.messages[0].text, "Hello")
        XCTAssertEqual(first.messages[0].attachments.count, 1)
        XCTAssertEqual(first.messages[0].attachments.first?.filename, "pic.png")
        XCTAssertEqual(first.messages[1].text, "Hi")
    }

    func test_upsert_replacesMessagesOnSecondCall() async throws {
        let persistence = try makePersistence()
        var thread = ConversationThread(title: "Thread")
        thread.messages = [
            ChatMessage(role: .user, text: "Q1"),
            ChatMessage(role: .assistant, text: "A1")
        ]
        try await persistence.upsert(thread)

        thread.messages = [ChatMessage(role: .user, text: "Q2")]
        thread.updatedAt = Date()
        try await persistence.upsert(thread)

        let loaded = try await persistence.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.messages.count, 1)
        XCTAssertEqual(loaded.first?.messages.first?.text, "Q2")
    }

    func test_delete_removesConversation() async throws {
        let persistence = try makePersistence()
        let thread = ConversationThread(title: "Doomed")
        try await persistence.upsert(thread)
        try await persistence.delete(id: thread.id)

        let remaining = try await persistence.loadAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_setFavorite_togglesFlag() async throws {
        let persistence = try makePersistence()
        let thread = ConversationThread(title: "Flagged", isFavorite: false)
        try await persistence.upsert(thread)
        try await persistence.setFavorite(id: thread.id, isFavorite: true)

        let loaded = try await persistence.conversation(id: thread.id)
        XCTAssertEqual(loaded?.isFavorite, true)
    }

    func test_loadAll_sortsByUpdatedAtDescending() async throws {
        let persistence = try makePersistence()
        let now = Date()
        let older = ConversationThread(
            title: "Older",
            createdAt: now.addingTimeInterval(-200),
            updatedAt: now.addingTimeInterval(-200)
        )
        let newer = ConversationThread(
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
        try await persistence.upsert(ConversationThread(title: "Seed"))

        let stream = await persistence.stream()
        var iterator = stream.makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first?.count, 1)
        XCTAssertEqual(first?.first?.title, "Seed")

        try await persistence.upsert(ConversationThread(title: "Second"))
        let next = await iterator.next()
        XCTAssertEqual(next?.count, 2)
        XCTAssertTrue(next?.contains(where: { $0.title == "Second" }) ?? false)
    }

    func test_savePromptPresets_roundTrips() async throws {
        let persistence = try makePersistence()
        let preset = PromptPreset(
            kind: .conversation,
            title: "Greeting",
            content: "Hello",
            isBuiltIn: false
        )
        try await persistence.savePromptPresets([preset])

        let loaded = try await persistence.loadPromptPresets()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Greeting")
    }

    func test_saveGlobalPinnedMemories_roundTrips() async throws {
        let persistence = try makePersistence()
        let pin = PinnedMemoryItem(
            text: "Use 24-hour clock",
            keywords: ["clock"],
            scope: .global
        )
        try await persistence.saveGlobalPinnedMemories([pin])

        let loaded = try await persistence.loadGlobalPinnedMemories()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.text, "Use 24-hour clock")
    }
}
