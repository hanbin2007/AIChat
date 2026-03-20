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

    func testSaveLoadAndDeleteConversationPersistsAcrossRestart() async throws {
        let rootURL = makeRootURL()
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

        _ = try await repository.save(conversation)

        let loaded = try await repository.loadConversations()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, conversationID)
        XCTAssertEqual(loaded.first?.title, "Test Chat")
        XCTAssertEqual(loaded.first?.isFavorite, true)

        try await repository.deleteConversation(id: conversationID)

        let restartedRepository = ConversationRepository(rootURL: rootURL)
        let afterDelete = try await restartedRepository.loadConversations()
        XCTAssertTrue(afterDelete.isEmpty)
    }

    func testSaveAndLoadPromptPresets() async throws {
        let repository = ConversationRepository(rootURL: makeRootURL())
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
        let repository = ConversationRepository(rootURL: makeRootURL())
        let deletedConversationID = UUID()
        let deletedAt = Date(timeIntervalSince1970: 1_763_000_000)

        try await repository.saveDeletedConversationTombstones([
            deletedConversationID: deletedAt
        ])

        let loadedTombstones = try await repository.loadDeletedConversationTombstones()

        XCTAssertEqual(loadedTombstones[deletedConversationID], deletedAt)
    }

    func testSaveHydratesAttachmentsAndMaterializesExportCache() async throws {
        let repository = ConversationRepository(rootURL: makeRootURL())
        let attachment = try makeImageAttachment(suggestedFilename: "persisted")
        let conversation = ConversationThread(
            title: "Image Chat",
            messages: [
                ChatMessage(role: .assistant, text: "Rendered image", attachments: [attachment])
            ]
        )

        let storedConversation = try await repository.save(conversation)
        let storedAttachment = try XCTUnwrap(storedConversation.messages.first?.attachments.first)
        let blobFilename = try XCTUnwrap(storedAttachment.blobFilename)
        let blobURL = repository.attachmentsDirectoryURL.appendingPathComponent(blobFilename, isDirectory: false)

        XCTAssertEqual(storedAttachment.data, attachment.data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))
        XCTAssertEqual(try Data(contentsOf: blobURL), attachment.data)

        let loadedConversations = try await repository.loadConversations()
        let loadedConversation = try XCTUnwrap(loadedConversations.first)
        let loadedAttachment = try XCTUnwrap(loadedConversation.messages.first?.attachments.first)

        XCTAssertEqual(loadedAttachment.blobFilename, storedAttachment.blobFilename)
        XCTAssertEqual(loadedAttachment.data, attachment.data)
    }

    func testDeletingConversationCascadesAndRemovesOnlyItsExportedAttachmentBlobs() async throws {
        let repository = ConversationRepository(rootURL: makeRootURL())
        let firstAttachment = try makeImageAttachment(suggestedFilename: "first")
        let secondAttachment = try makeImageAttachment(suggestedFilename: "second")
        let firstConversation = ConversationThread(
            title: "Delete First",
            messages: [ChatMessage(role: .assistant, text: "First", attachments: [firstAttachment])]
        )
        let secondConversation = ConversationThread(
            title: "Keep Second",
            messages: [ChatMessage(role: .assistant, text: "Second", attachments: [secondAttachment])]
        )

        let storedFirstConversation = try await repository.save(firstConversation)
        let storedSecondConversation = try await repository.save(secondConversation)

        let firstBlobFilename = try XCTUnwrap(storedFirstConversation.messages.first?.attachments.first?.blobFilename)
        let secondBlobFilename = try XCTUnwrap(storedSecondConversation.messages.first?.attachments.first?.blobFilename)
        let firstBlobURL = repository.attachmentsDirectoryURL.appendingPathComponent(firstBlobFilename, isDirectory: false)
        let secondBlobURL = repository.attachmentsDirectoryURL.appendingPathComponent(secondBlobFilename, isDirectory: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBlobURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondBlobURL.path))

        try await repository.deleteConversation(id: firstConversation.id)

        let restartedRepository = ConversationRepository(rootURL: repository.resolvedRootURL)
        let remainingConversations = try await restartedRepository.loadConversations()

        XCTAssertEqual(remainingConversations.map(\.id), [secondConversation.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstBlobURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondBlobURL.path))
    }

    func testImportAttachmentBlobHydratesConversationBeforePersist() async throws {
        let rootURL = makeRootURL()
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

    func testLegacyJSONStoreImportsIntoSwiftDataOnFirstLoad() async throws {
        let rootURL = makeRootURL()
        let attachment = try makeImageAttachment(suggestedFilename: "legacy")
        let blobFilename = "legacy-\(attachment.id.uuidString).png"
        let attachmentsDirectoryURL = rootURL.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDirectoryURL, withIntermediateDirectories: true)
        try attachment.data.write(
            to: attachmentsDirectoryURL.appendingPathComponent(blobFilename, isDirectory: false),
            options: [.atomic]
        )

        let legacyConversation = ConversationThread(
            title: "Legacy",
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "Legacy payload",
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
        let globalPinnedMemory = PinnedMemoryItem(
            text: "请始终使用中文。",
            keywords: ["中文"],
            scope: .global
        )
        let preset = PromptPreset(
            kind: .conversation,
            title: "Legacy Preset",
            content: "Be concise."
        )
        let tombstoneID = UUID()
        let tombstoneDate = Date(timeIntervalSince1970: 1_763_000_123)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try encoder.encode(legacyConversation).write(
            to: rootURL.appendingPathComponent("\(legacyConversation.id.uuidString).json", isDirectory: false),
            options: [.atomic]
        )
        try encoder.encode([globalPinnedMemory]).write(
            to: rootURL.appendingPathComponent("_global_pinned_memories.json", isDirectory: false),
            options: [.atomic]
        )
        try encoder.encode([preset]).write(
            to: rootURL.appendingPathComponent("_prompt_presets.json", isDirectory: false),
            options: [.atomic]
        )
        try encoder.encode([
            LegacyDeletedConversationTombstone(id: tombstoneID, deletedAt: tombstoneDate)
        ]).write(
            to: rootURL.appendingPathComponent("_deleted_conversation_tombstones.json", isDirectory: false),
            options: [.atomic]
        )

        let repository = ConversationRepository(rootURL: rootURL)

        let conversations = try await repository.loadConversations()
        let globalPinnedMemories = try await repository.loadGlobalPinnedMemories()
        let promptPresets = try await repository.loadPromptPresets()
        let tombstones = try await repository.loadDeletedConversationTombstones()

        XCTAssertEqual(conversations.map(\.id), [legacyConversation.id])
        XCTAssertEqual(conversations.first?.messages.first?.attachments.first?.data, attachment.data)
        XCTAssertEqual(globalPinnedMemories.map(\.id), [globalPinnedMemory.id])
        XCTAssertTrue(promptPresets.contains(where: { $0.id == preset.id }))
        XCTAssertEqual(tombstones[tombstoneID], tombstoneDate)

        try await repository.deleteConversation(id: legacyConversation.id)
        let restartedRepository = ConversationRepository(rootURL: rootURL)
        let restartedConversations = try await restartedRepository.loadConversations()
        XCTAssertTrue(restartedConversations.isEmpty)
    }

    private func makeRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
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

private struct LegacyDeletedConversationTombstone: Codable {
    let id: UUID
    let deletedAt: Date
}
