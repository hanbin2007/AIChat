//
//  ConversationRepositoryTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import XCTest
@testable import AIChat_Watch_App

final class ConversationRepositoryTests: XCTestCase {
    func testSaveLoadAndDeleteConversation() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let conversationID = UUID()
        let conversation = ConversationThread(
            id: conversationID,
            title: "Test Chat",
            createdAt: .now,
            updatedAt: .now,
            isFavorite: true,
            messages: [
                ChatMessage(role: .user, text: "Hello watch")
            ]
        )

        try await repository.save(conversation)

        let loaded = try await repository.loadConversations()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conversationID)
        XCTAssertEqual(loaded.first?.title, "Test Chat")
        XCTAssertEqual(loaded.first?.isFavorite, true)

        try await repository.deleteConversation(id: conversationID)
        let afterDelete = try await repository.loadConversations()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testSaveAndLoadPromptPresets() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let preset = PromptPreset(
            kind: .conversation,
            title: "Meeting Summary",
            content: "Summarize the discussion into decisions and action items."
        )

        try await repository.savePromptPresets(PromptPreset.resolvedLibrary(from: [preset]))

        let loadedPresets = try await repository.loadPromptPresets()

        XCTAssertTrue(
            loadedPresets.contains(where: { $0.title == "Meeting Summary" && $0.kind == .conversation })
        )
    }
}
