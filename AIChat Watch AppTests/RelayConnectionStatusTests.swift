//
//  RelayConnectionStatusTests.swift
//  AIChat Watch AppTests
//
//  Covers the relay connection-status state machine and the
//  `RelayAIClient` lifecycle emissions in the relay-only app path.
//

import XCTest
@testable import AIChat_Watch_App

// NOTE: Every test here is `async throws` per CLAUDE.md — watchOS 26
// segfaults the first synchronous `@MainActor` test in the test host
// process. Keep the marker even when the body is synchronous.

final class RelayConnectionStatusTests: XCTestCase {
    // MARK: - State machine

    @MainActor
    func testColdStartStatusIsUnknown() async throws {
        // `relayConnectionStatus` must NOT lie and claim `online`
        // before any request has ever been made — the cold-start
        // contract.
        let store = ChatStore.previewStore(
            conversations: [],
            configuration: Self.makeRelayConfiguration()
        )

        XCTAssertEqual(store.relayConnectionStatus, .unknown)
        XCTAssertNil(store.relayLastSuccessAt)
        XCTAssertNil(store.relayLastFailureAt)
    }

    @MainActor
    func testHandlerTransitionsUnknownToConnectingToOnline() async throws {
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        handler.report(.connecting)
        handler.report(.online)

        try await collector.waitForCount(2)
        XCTAssertEqual(collector.snapshot(), [.connecting, .online])
    }

    @MainActor
    func testHandlerTransitionsConnectingToOfflineCarriesReason() async throws {
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        handler.report(.connecting)
        handler.report(.offline(reason: "socket closed"))

        try await collector.waitForCount(2)
        XCTAssertEqual(
            collector.snapshot(),
            [.connecting, .offline(reason: "socket closed")]
        )
    }

    @MainActor
    func testOnlineThenNewRequestReentersConnecting() async throws {
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        handler.report(.connecting)
        handler.report(.online)
        handler.report(.connecting)
        handler.report(.online)

        try await collector.waitForCount(4)
        XCTAssertEqual(
            collector.snapshot(),
            [.connecting, .online, .connecting, .online]
        )
    }

    @MainActor
    func testDuplicateStatusIsCoalesced() async throws {
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        handler.report(.connecting)
        handler.report(.connecting)
        handler.report(.connecting)

        // Give the actor hop a chance to drain.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(collector.snapshot(), [.connecting])
    }

    @MainActor
    func testRapidFlapIsDebouncedToLatestStatus() async throws {
        // 10 alternating transitions within the debounce window should
        // deliver the first one immediately and then a single
        // coalesced trailing emission for the final state — not 10
        // individual notifications.
        let handler = RelayConnectionStatusHandler(debounceInterval: 0.2)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        handler.report(.connecting)
        for _ in 0..<4 {
            handler.report(.online)
            handler.report(.offline(reason: "flap"))
        }
        handler.report(.online)

        // Wait past the debounce window plus a small safety margin.
        try await Task.sleep(nanoseconds: 400_000_000)

        let delivered = collector.snapshot()
        XCTAssertLessThanOrEqual(delivered.count, 2, "Expected debounce to coalesce rapid flap into at most two deliveries. Got: \(delivered)")
        XCTAssertEqual(delivered.first, .connecting)
        XCTAssertEqual(delivered.last, .online)
    }

    // MARK: - ChatStore integration (relay mode only)

    @MainActor
    func testRelayConfiguredStoreAppliesStatusTransitions() async throws {
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let store = Self.makeRelayStore(handler: handler)

        XCTAssertEqual(store.relayConnectionStatus, .unknown)

        handler.report(.connecting)
        try await Self.waitForStatus(.connecting, on: store)
        XCTAssertEqual(store.relayConnectionStatus, .connecting)

        handler.report(.online)
        try await Self.waitForStatus(.online, on: store)
        XCTAssertEqual(store.relayConnectionStatus, .online)
        XCTAssertNotNil(store.relayLastSuccessAt)

        handler.report(.offline(reason: "timeout"))
        try await Self.waitForStatus(.offline(reason: "timeout"), on: store)
        XCTAssertEqual(store.relayConnectionStatus, .offline(reason: "timeout"))
        XCTAssertNotNil(store.relayLastFailureAt)
    }

    // MARK: - RelayAIClient lifecycle (integration)

    @MainActor
    func testRelayAIClientMissingConfigurationEmitsOffline() async throws {
        // Force the "missing configuration" error path — no base URL
        // means the client throws before making any network call and
        // must still emit `.offline(reason:)`.
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let handler = RelayConnectionStatusHandler(debounceInterval: 0)
        let collector = StatusCollector()
        handler.setOnChange { [weak collector] status in
            collector?.append(status)
        }

        var client = RelayAIClient(configuration: configuration)
        client.statusHandler = handler

        let conversation = ConversationThread(
            id: UUID(),
            title: "Relay Test",
            messages: [ChatMessage(role: .user, text: "hi")]
        )

        let stream = client.streamReply(for: conversation)

        do {
            for try await _ in stream {
                XCTFail("Expected stream to fail with missingConfiguration")
            }
            XCTFail("Expected throwing stream")
        } catch {
            // Expected — missing configuration.
        }

        try await collector.waitForOfflineEmission()
        let delivered = collector.snapshot()
        guard case .offline = delivered.last else {
            XCTFail("Expected terminal `.offline(reason:)` transition. Got: \(delivered)")
            return
        }
    }

    // MARK: - Helpers

    private static func makeRelayConfiguration(
        baseURL: URL? = URL(string: "https://relay.example.test")
    ) -> AppConfiguration {
        AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: baseURL,
            relayBearerToken: "test-token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
    }

    @MainActor
    private static func makeRelayStore(
        handler: RelayConnectionStatusHandler
    ) -> ChatStore {
        let configuration = makeRelayConfiguration()
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatRelayStatusTest-\(UUID().uuidString)", isDirectory: true)
        )

        return ChatStore(
            repository: repository,
            aiService: NoOpStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(isEnabled: false),
            replyPersistenceController: NoopReplyPersistenceController.shared,
            relayConnectionStatusHandler: handler
        )
    }

    @MainActor
    private static func waitForStatus(
        _ expected: RelayConnectionStatus,
        on store: ChatStore,
        timeout: TimeInterval = 1.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if store.relayConnectionStatus == expected {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for status \(expected). Current: \(store.relayConnectionStatus)")
    }
}

// MARK: - Test doubles

/// Thread-safe collector for status transitions delivered on the main
/// actor. Isolated via a lock so tests can assert snapshots without
/// risking data races between the handler's main-actor hop and the
/// test body.
private final class StatusCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [RelayConnectionStatus] = []

    func append(_ status: RelayConnectionStatus) {
        lock.lock()
        statuses.append(status)
        lock.unlock()
    }

    func snapshot() -> [RelayConnectionStatus] {
        lock.lock()
        defer { lock.unlock() }
        return statuses
    }

    func waitForCount(_ expected: Int, timeout: TimeInterval = 1.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if snapshot().count >= expected {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for \(expected) status updates. Got: \(snapshot())")
    }

    func waitForOfflineEmission(timeout: TimeInterval = 1.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .offline = snapshot().last {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for offline emission. Got: \(snapshot())")
    }
}

private struct NoOpStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
