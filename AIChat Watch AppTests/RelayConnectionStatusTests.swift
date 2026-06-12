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

    func testRelayTranscriptionUsesInjectedCredentialProvider() async throws {
        let configuration = Self.makeRelayConfiguration()
        let recorder = RelayRequestRecorder()
        let session = Self.makeRecordingSession(recorder: recorder)
        var service = RelayTranscriptionService(
            configuration: configuration,
            credentialProvider: StaticRelayCredentialProvider(token: "rk_provider_token")
        )
        service.session = session

        let audio = try ChatAttachment.makeRecordedAudio(
            from: Data([0x01, 0x02, 0x03]),
            suggestedFilename: "voice.wav",
            durationSeconds: 1
        )
        let conversation = ConversationThread(
            id: UUID(),
            title: "Credential Provider",
            messages: [ChatMessage(role: .user, text: "transcribe")]
        )

        _ = try await service.transcribeUserAudio(
            audio,
            in: conversation,
            using: VoiceTranscriptionConfiguration(model: "gemini-3-flash-preview")
        )

        XCTAssertEqual(recorder.authorizationHeader, "Bearer rk_provider_token")
    }

    func testRelayChatRequestUsesInjectedCredentialProvider() throws {
        let configuration = Self.makeRelayConfiguration()
        let conversation = ConversationThread(
            id: UUID(),
            title: "Credential Provider",
            messages: [ChatMessage(role: .user, text: "send")]
        )
        let client = RelayAIClient(
            configuration: configuration,
            credentialProvider: StaticRelayCredentialProvider(token: "rk_chat_provider_token")
        )

        let request = try client.makeStreamRequest(for: conversation)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rk_chat_provider_token")
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

    private static func makeRecordingSession(recorder: RelayRequestRecorder) -> URLSession {
        RecordingURLProtocol.register(recorder)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        configuration.httpAdditionalHeaders = [
            RecordingURLProtocol.recorderHeader: recorder.identifier.uuidString
        ]
        return URLSession(configuration: configuration)
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

private struct StaticRelayCredentialProvider: RelayCredentialProviding {
    var token: String?

    func relayBearerToken() -> String? {
        token
    }
}

private final class RelayRequestRecorder: @unchecked Sendable {
    let identifier = UUID()
    private let lock = NSLock()
    private var capturedAuthorizationHeader: String?

    var authorizationHeader: String? {
        lock.lock()
        defer { lock.unlock() }
        return capturedAuthorizationHeader
    }

    func record(_ request: URLRequest) {
        lock.lock()
        capturedAuthorizationHeader = request.value(forHTTPHeaderField: "Authorization")
        lock.unlock()
    }
}

private final class RecordingURLProtocol: URLProtocol {
    static let recorderHeader = "X-AIChat-Test-Recorder"
    private static let lock = NSLock()
    private static var recorders: [String: RelayRequestRecorder] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: recorderHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let recorderID = request.value(forHTTPHeaderField: Self.recorderHeader),
           let recorder = Self.recorder(for: recorderID) {
            recorder.record(request)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://relay.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"ok"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func register(_ recorder: RelayRequestRecorder) {
        lock.lock()
        recorders[recorder.identifier.uuidString] = recorder
        lock.unlock()
    }

    private static func recorder(for identifier: String) -> RelayRequestRecorder? {
        lock.lock()
        defer { lock.unlock() }
        return recorders[identifier]
    }
}
