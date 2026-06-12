//
//  ChatStoreBlankoutRegressionTests.swift
//  AIChat Watch AppTests
//
//  Regression tests for the "conversation list randomly goes blank" class of
//  bug. Two independent code paths used to be able to wipe the user's
//  conversation list without any record:
//
//    1. `loadConversationsIfNeeded()` flipped `hasLoadedConversations = true`
//       *before* the load body ran, so any transient error (cold disk I/O,
//       tombstone decode hiccup, sync-startup contention) left the flag true
//       and the UI blank — every subsequent call early-returned, so the list
//       never recovered for the life of the process.
//
//    2. `applySyncStoreState(_:)` unconditionally replaced the in-memory
//       conversation list with whatever the sync layer produced. A merged
//       state of `[]` with no tombstones — which is never a legitimate
//       outcome — would silently erase the user's history.
//
//  These tests pin the contracts that prevent both regressions.
//

import Combine
import Foundation
import XCTest
@testable import AIChat_Watch_App

final class ChatStoreBlankoutRegressionTests: XCTestCase {

    // NOTE: All tests here are `async throws` even when the logic doesn't
    // require it. The watchOS 26 test runner has a launch-race bug where
    // the first sync `@MainActor` test per process segfaults the app host
    // while async ones survive. Keeping every test async works around it.

    @MainActor
    func testApplySyncStoreStateRefusesEmptyWipeWithNoTombstones() async throws {
        let store = try await makeStoreWithSeededConversation(title: "Seeded chat")
        let seededID = try XCTUnwrap(store.conversations.first?.id)

        // Simulate a broken sync that reports "zero conversations, zero
        // tombstones" while the user still has live history locally.
        let emptyState = ConversationSyncStoreState(
            conversations: [],
            deletedConversationTombstones: [:],
            globalPinnedMemories: [],
            promptPresets: PromptPreset.builtInPresets
        )
        store.syncCoordinator.onApplySyncStoreState?(emptyState)

        XCTAssertEqual(store.conversations.count, 1,
                       "Guard must reject suspicious empty-wipe and keep local conversations.")
        XCTAssertEqual(store.conversations.first?.id, seededID)
        XCTAssertNotNil(store.startupError,
                        "User-visible surface must flag that a sync update was refused.")
    }

    @MainActor
    func testApplySyncStoreStateAllowsLegitimateDeletionWithTombstone() async throws {
        let store = try await makeStoreWithSeededConversation(title: "Seeded chat")
        let seededID = try XCTUnwrap(store.conversations.first?.id)

        // Legitimate "user deleted the conversation on another device": the
        // merged state carries a tombstone accounting for the removal.
        let legitimateDeletion = ConversationSyncStoreState(
            conversations: [],
            deletedConversationTombstones: [seededID: Date()],
            globalPinnedMemories: [],
            promptPresets: PromptPreset.builtInPresets
        )
        store.syncCoordinator.onApplySyncStoreState?(legitimateDeletion)

        XCTAssertTrue(store.conversations.isEmpty,
                      "Tombstone-backed deletions must still be applied.")
    }

    @MainActor
    func testApplySyncStoreStateNoOpWhenLocalAlreadyEmpty() async throws {
        let store = try await makeEmptyStore()

        // Empty → empty is not a wipe; the guard must not mis-fire here.
        let emptyState = ConversationSyncStoreState()
        store.syncCoordinator.onApplySyncStoreState?(emptyState)

        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNil(store.startupError,
                     "Empty-to-empty sync is legitimate and must not raise a startup error.")
    }

    @MainActor
    func testLoadConversationsIfNeededRetriesAfterFailure() async throws {
        // Pin the exact bug that caused "conversation list randomly blanks":
        // when the first load throws, `hasLoadedConversations` used to be
        // already true, so every later call short-circuited and the view
        // stayed blank for the life of the process. With the fix, a failed
        // load leaves the flag false and the next call re-enters the load
        // body — observable here via `isInitialConversationLoadInProgress`
        // toggling on each attempt.
        let rootURL = makeTempRootURL()
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        // Poison the SwiftData store file with garbage so `ModelContainer`
        // init fails and every `loadConversations()` call throws.
        let sqliteURL = rootURL.appendingPathComponent("ConversationStore.sqlite", isDirectory: false)
        try Data("not a sqlite database".utf8).write(to: sqliteURL, options: [.atomic])

        let configuration = makeTestConfiguration()
        let repository = ConversationRepository(configuration: configuration, rootURL: rootURL)
        let store = ChatStore(
            repository: repository,
            aiService: BlankoutRegressionEchoAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )

        var loadInProgressTransitions = 0
        let cancellable = store.$isInitialConversationLoadInProgress
            .dropFirst() // skip the initial `false` published on subscribe
            .sink { _ in loadInProgressTransitions += 1 }
        defer { cancellable.cancel() }

        await store.loadConversationsIfNeeded()
        XCTAssertTrue(store.conversations.isEmpty)
        XCTAssertNotNil(store.startupError,
                        "Poisoned repository must surface a startup error.")
        let transitionsAfterFirstCall = loadInProgressTransitions

        await store.loadConversationsIfNeeded()
        XCTAssertGreaterThan(loadInProgressTransitions, transitionsAfterFirstCall,
                             "Second call must re-enter the load body after a transient failure; the old code short-circuited forever.")
    }

    // MARK: - Helpers

    @MainActor
    private func makeEmptyStore() async throws -> ChatStore {
        let configuration = makeTestConfiguration()
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: makeTempRootURL()
        )
        let store = ChatStore(
            repository: repository,
            aiService: BlankoutRegressionEchoAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await store.loadConversationsIfNeeded()
        return store
    }

    @MainActor
    private func makeStoreWithSeededConversation(title: String) async throws -> ChatStore {
        let configuration = makeTestConfiguration()
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: makeTempRootURL()
        )
        _ = try await repository.save(
            ConversationThread(
                title: title,
                createdAt: .now,
                updatedAt: .now,
                messages: [ChatMessage(role: .user, text: "Seed")]
            )
        )
        let store = ChatStore(
            repository: repository,
            aiService: BlankoutRegressionEchoAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await store.loadConversationsIfNeeded()
        return store
    }

    private func makeTempRootURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatBlankoutTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeTestConfiguration() -> AppConfiguration {
        AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
    }
}

private struct BlankoutRegressionEchoAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
