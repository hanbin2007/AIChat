//
//  ICloudConversationSyncServiceTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import XCTest
@testable import AIChat_Watch_App

final class ICloudConversationSyncServiceTests: XCTestCase {
    func testReconcileMergesLocalAndCloudStateAndPersistsUnion() async throws {
        let rootURL = makeTemporaryRootURL(prefix: "AIChatTests-iCloud")
        let configuration = makeSyncConfiguration()
        let cloudRepository = ConversationRepository(configuration: configuration, rootURL: rootURL)
        let syncService = ICloudConversationSyncService(configuration: configuration, rootURL: rootURL)

        let sharedConversationID = UUID()
        let remoteOnlyConversationID = UUID()
        let localOnlyConversationID = UUID()
        let remotePinnedMemory = PinnedMemoryItem(text: "remote", scope: .global)
        let localPinnedMemory = PinnedMemoryItem(text: "local", scope: .global)
        let remotePreset = PromptPreset(kind: .conversation, title: "Remote", content: "Cloud side")
        let localPreset = PromptPreset(kind: .conversation, title: "Local", content: "Device side")

        _ = try await cloudRepository.save(
            ConversationThread(
                id: sharedConversationID,
                title: "Remote Newer",
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 40),
                messages: [ChatMessage(role: .assistant, text: "remote newer")]
            )
        )
        _ = try await cloudRepository.save(
            ConversationThread(
                id: remoteOnlyConversationID,
                title: "Remote Only",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 30),
                messages: [ChatMessage(role: .assistant, text: "cloud record")]
            )
        )
        try await cloudRepository.saveGlobalPinnedMemories([remotePinnedMemory])
        try await cloudRepository.savePromptPresets([remotePreset])

        let localState = ConversationSyncStoreState(
            conversations: [
                ConversationThread(
                    id: sharedConversationID,
                    title: "Local Older",
                    createdAt: Date(timeIntervalSince1970: 20),
                    updatedAt: Date(timeIntervalSince1970: 35),
                    messages: [ChatMessage(role: .assistant, text: "local older")]
                ),
                ConversationThread(
                    id: localOnlyConversationID,
                    title: "Local Only",
                    createdAt: Date(timeIntervalSince1970: 50),
                    updatedAt: Date(timeIntervalSince1970: 60),
                    messages: [ChatMessage(role: .user, text: "device record")]
                )
            ],
            globalPinnedMemories: [localPinnedMemory],
            promptPresets: [localPreset]
        )

        let mergedState = try await syncService.reconcile(localState: localState)
        let mergedConversationIDs = mergedState.conversations.map(\.id)

        XCTAssertEqual(
            Set(mergedConversationIDs),
            Set([sharedConversationID, remoteOnlyConversationID, localOnlyConversationID])
        )
        XCTAssertEqual(
            mergedState.conversations.first(where: { $0.id == sharedConversationID })?.title,
            "Remote Newer"
        )
        XCTAssertEqual(Set(mergedState.globalPinnedMemories.map(\.id)), Set([remotePinnedMemory.id, localPinnedMemory.id]))
        XCTAssertTrue(mergedState.promptPresets.contains(where: { $0.id == remotePreset.id }))
        XCTAssertTrue(mergedState.promptPresets.contains(where: { $0.id == localPreset.id }))

        let persistedCloudState = try await syncService.fetchState()
        XCTAssertEqual(persistedCloudState, mergedState)
    }

    func testReconcilePrefersNewestDeletionTombstoneOverConversationCopies() async throws {
        let rootURL = makeTemporaryRootURL(prefix: "AIChatTests-iCloud-Tombstone")
        let configuration = makeSyncConfiguration()
        let cloudRepository = ConversationRepository(configuration: configuration, rootURL: rootURL)
        let syncService = ICloudConversationSyncService(configuration: configuration, rootURL: rootURL)
        let conversationID = UUID()
        let deletedAt = Date(timeIntervalSince1970: 100)

        _ = try await cloudRepository.save(
            ConversationThread(
                id: conversationID,
                title: "Cloud Copy",
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 120),
                messages: [ChatMessage(role: .assistant, text: "should be deleted")]
            )
        )
        try await cloudRepository.saveDeletedConversationTombstones([conversationID: deletedAt])

        let localState = ConversationSyncStoreState(
            conversations: [
                ConversationThread(
                    id: conversationID,
                    title: "Local Copy",
                    createdAt: Date(timeIntervalSince1970: 10),
                    updatedAt: Date(timeIntervalSince1970: 130),
                    messages: [ChatMessage(role: .assistant, text: "also deleted")]
                )
            ]
        )

        let mergedState = try await syncService.reconcile(localState: localState)

        XCTAssertTrue(mergedState.conversations.isEmpty)
        XCTAssertEqual(mergedState.deletedConversationTombstones[conversationID], deletedAt)

        let persistedCloudState = try await syncService.fetchState()
        XCTAssertEqual(persistedCloudState?.conversations, [])
        XCTAssertEqual(persistedCloudState?.deletedConversationTombstones[conversationID], deletedAt)
    }

    func testSyncSummaryDetectsMissingAttachmentBlobData() throws {
        let attachment = try makeOnePixelImageAttachment(suggestedFilename: "sync")
        let blobFilename = "blob-\(attachment.id.uuidString).png"
        let hydratedConversation = ConversationThread(
            title: "Hydrated",
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "image",
                    attachments: [
                        ChatAttachment(
                            id: attachment.id,
                            kind: .image,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: attachment.data,
                            blobFilename: blobFilename,
                            pixelWidth: attachment.pixelWidth,
                            pixelHeight: attachment.pixelHeight
                        )
                    ]
                )
            ]
        )
        let metadataOnlyConversation = ConversationThread(
            id: hydratedConversation.id,
            title: hydratedConversation.title,
            createdAt: hydratedConversation.createdAt,
            updatedAt: hydratedConversation.updatedAt,
            messages: [
                ChatMessage(
                    id: try XCTUnwrap(hydratedConversation.messages.first?.id),
                    role: .assistant,
                    text: "image",
                    createdAt: try XCTUnwrap(hydratedConversation.messages.first?.createdAt),
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

        let hydratedSummary = ConversationSyncStoreState(conversations: [hydratedConversation]).summary
        let metadataOnlySummary = ConversationSyncStoreState(conversations: [metadataOnlyConversation]).summary

        XCTAssertNotEqual(hydratedSummary.digest, metadataOnlySummary.digest)
        XCTAssertEqual(hydratedSummary.attachmentCount, metadataOnlySummary.attachmentCount)
    }

    private func makeSyncConfiguration() -> AppConfiguration {
        makeDirectModeAppConfiguration(geminiModel: "gemini-3-flash-preview")
    }
}
