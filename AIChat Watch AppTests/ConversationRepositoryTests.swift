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
    private let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW2QAAAAASUVORK5CYII="

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

    func testSaveAndLoadDeletedConversationTombstones() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let deletedConversationID = UUID()
        let deletedAt = Date(timeIntervalSince1970: 1_763_000_000)

        try await repository.saveDeletedConversationTombstones([
            deletedConversationID: deletedAt
        ])

        let loadedTombstones = try await repository.loadDeletedConversationTombstones()

        XCTAssertEqual(loadedTombstones[deletedConversationID], deletedAt)
    }

    func testSaveReturnsBlobBackedConversationAndHydratesOnLoad() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let attachment = try makeImageAttachment(suggestedFilename: "persisted")
        let conversation = ConversationThread(
            title: "Image Chat",
            messages: [
                ChatMessage(role: .assistant, text: "Rendered image", attachments: [attachment])
            ]
        )

        let storedConversation = try await repository.save(conversation)
        let storedAttachment = try XCTUnwrap(storedConversation.messages.first?.attachments.first)

        XCTAssertTrue(storedAttachment.data.isEmpty)
        XCTAssertNotNil(storedAttachment.blobFilename)

        let loadedConversations = try await repository.loadConversations()
        let loadedConversation = try XCTUnwrap(loadedConversations.first)
        let loadedAttachment = try XCTUnwrap(loadedConversation.messages.first?.attachments.first)

        XCTAssertEqual(loadedAttachment.blobFilename, storedAttachment.blobFilename)
        XCTAssertEqual(loadedAttachment.data, attachment.data)
    }

    func testSaveRemovesObsoleteAttachmentBlob() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let firstAttachment = try makeImageAttachment(suggestedFilename: "first")
        let replacementAttachment = try makeImageAttachment(suggestedFilename: "replacement")
        let conversationID = UUID()
        let originalConversation = ConversationThread(
            id: conversationID,
            title: "Blob Cleanup",
            messages: [
                ChatMessage(role: .assistant, text: "First", attachments: [firstAttachment])
            ]
        )

        let storedOriginalConversation = try await repository.save(originalConversation)
        let removedBlobFilename = try XCTUnwrap(storedOriginalConversation.messages.first?.attachments.first?.blobFilename)
        let removedBlobURL = repository.attachmentsDirectoryURL
            .appendingPathComponent(removedBlobFilename, isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: removedBlobURL.path))

        let replacementConversation = ConversationThread(
            id: conversationID,
            title: "Blob Cleanup",
            messages: [
                ChatMessage(role: .assistant, text: "Replacement", attachments: [replacementAttachment])
            ]
        )

        let storedReplacementConversation = try await repository.save(replacementConversation)
        let replacementBlobFilename = try XCTUnwrap(
            storedReplacementConversation.messages.first?.attachments.first?.blobFilename
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: removedBlobURL.path))
        XCTAssertNotEqual(replacementBlobFilename, removedBlobFilename)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: repository.attachmentsDirectoryURL
                    .appendingPathComponent(replacementBlobFilename, isDirectory: false)
                    .path
            )
        )
    }

    func testDeleteConversationRemovesPersistedAttachmentBlobs() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let attachment = try makeImageAttachment(suggestedFilename: "delete")
        let conversation = ConversationThread(
            title: "Delete With Attachment",
            messages: [
                ChatMessage(role: .assistant, text: "Image", attachments: [attachment])
            ]
        )

        let storedConversation = try await repository.save(conversation)
        let blobFilename = try XCTUnwrap(storedConversation.messages.first?.attachments.first?.blobFilename)
        let blobURL = repository.attachmentsDirectoryURL.appendingPathComponent(blobFilename, isDirectory: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))

        try await repository.deleteConversation(id: conversation.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
    }

    func testImportAttachmentBlobHydratesConversation() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = ConversationRepository(rootURL: rootURL)
        let attachment = try makeImageAttachment(suggestedFilename: "remote")
        let blobFilename = "remote-attachment.png"
        let temporaryFileURL = rootURL.appendingPathComponent("incoming.png", isDirectory: false)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try attachment.data.write(to: temporaryFileURL, options: [.atomic])

        _ = try await repository.importAttachmentBlob(from: temporaryFileURL, as: blobFilename)

        let remoteConversation = ConversationThread(
            title: "Hydrate Remote",
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "Remote image",
                    attachments: [
                        ChatAttachment(
                            id: attachment.id,
                            kind: .image,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: Data(),
                            blobFilename: blobFilename,
                            pixelWidth: attachment.pixelWidth,
                            pixelHeight: attachment.pixelHeight
                        )
                    ]
                )
            ]
        )

        let hydratedConversation = await repository.hydrateAttachments(in: remoteConversation)

        XCTAssertEqual(
            hydratedConversation.messages.first?.attachments.first?.data,
            attachment.data
        )
    }

    private func makeImageAttachment(suggestedFilename: String) throws -> ChatAttachment {
        let data = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        return try ChatAttachment.makeModelGeneratedImage(
            from: data,
            mimeType: "image/png",
            suggestedFilename: suggestedFilename
        )
    }
}
