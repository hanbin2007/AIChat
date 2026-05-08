//
//  ConversationDetailViewModelStreamingTests.swift
//  AIChat Watch AppTests
//
//  Integration test covering §1.x / §2.x wiring inside
//  `ConversationDetailViewModel.send`:
//    - background session begin/end bracketing
//    - autoScroll driven on each pacer-yielded snapshot
//    - haptic + notification fired on success path only
//    - notification skipped when app foregrounded
//    - cancel cleanly tears down the background session
//

import XCTest
import UserNotifications
@testable import AIChat_Watch_App

@MainActor
final class ConversationDetailViewModelStreamingTests: XCTestCase {

    func test_send_beginsAndEndsBackgroundSession() async throws {
        let harness = try makeHarness()
        harness.chat.script = [.yieldThenFinish([
            ConversationThread.fixtureWithAssistantPlaceholder(text: "Done.")
        ])]

        harness.vm.send(text: "hi", attachments: [])
        await harness.waitUntilIdle()

        XCTAssertEqual(harness.backgroundHandle.startCount, 1)
        XCTAssertEqual(harness.backgroundHandle.invalidateCount, 1)
    }

    func test_send_drivesAutoScrollOnEachUpdate() async throws {
        let harness = try makeHarness()
        let snap = ConversationThread.fixtureWithAssistantPlaceholder(text: "Hi there")
        harness.chat.script = [.yieldThenFinish([snap])]

        harness.vm.send(text: "hi", attachments: [])
        await harness.waitUntilIdle()

        XCTAssertEqual(harness.vm.autoScroll.anchorMessageID, snap.messages.last?.id)
    }

    func test_send_playsHapticOnSuccess() async throws {
        let harness = try makeHarness()
        harness.chat.script = [.yieldThenFinish([
            ConversationThread.fixtureWithAssistantPlaceholder(text: "Done.")
        ])]

        harness.vm.send(text: "hi", attachments: [])
        await harness.waitUntilIdle()

        XCTAssertEqual(harness.haptic.playSuccessCount, 1)
    }

    func test_send_doesNotPlayHapticOnFailure() async throws {
        let harness = try makeHarness()
        harness.chat.script = [.immediateFail(StubError.boom)]

        harness.vm.send(text: "hi", attachments: [])
        await harness.waitUntilIdle()

        XCTAssertEqual(harness.haptic.playSuccessCount, 0)
        XCTAssertEqual(harness.backgroundHandle.invalidateCount, 1)
        XCTAssertTrue(harness.vm.autoScroll.shouldFollow,
                      "autoScroll must be re-armed even on failure so the next turn isn't frozen")
    }

    func test_send_skipsNotificationWhenForeground() async throws {
        let harness = try makeHarness(foreground: true)
        harness.chat.script = [.yieldThenFinish([
            ConversationThread.fixtureWithAssistantPlaceholder(text: "Done.")
        ])]

        harness.vm.send(text: "hi", attachments: [])
        await harness.waitUntilIdle()

        XCTAssertEqual(harness.notifications.added.count, 0)
    }

    func test_cancelStream_tearsDownBackgroundSession() async throws {
        let harness = try makeHarness()
        // Long script with a hung continuation so cancel happens mid-stream.
        harness.chat.script = [.yieldThenFinish([
            ConversationThread.fixtureWithAssistantPlaceholder(text: "Hi"),
            ConversationThread.fixtureWithAssistantPlaceholder(text: "Hi there world this is a long one")
        ])]

        harness.vm.send(text: "hi", attachments: [])
        // Let the task start and begin the background session.
        try await Task.sleep(nanoseconds: 50_000_000)
        harness.vm.cancelStream()
        // Wait for invalidation.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(harness.backgroundHandle.invalidateCount, 1)
    }

    // MARK: - Harness

    @MainActor
    final class Harness {
        let vm: ConversationDetailViewModel
        let chat: StubChatService
        let backgroundHandle: StubBackgroundHandle
        let haptic: CountingHaptic
        let notifications: RecordingNotificationCenter

        init(
            vm: ConversationDetailViewModel,
            chat: StubChatService,
            backgroundHandle: StubBackgroundHandle,
            haptic: CountingHaptic,
            notifications: RecordingNotificationCenter
        ) {
            self.vm = vm
            self.chat = chat
            self.backgroundHandle = backgroundHandle
            self.haptic = haptic
            self.notifications = notifications
        }

        func waitUntilIdle(timeout: Duration = .seconds(2)) async {
            let start = Date()
            while Date().timeIntervalSince(start) < 2.0 {
                if vm.sendState == .idle || vm.sendState != .streaming && vm.sendState != .sending {
                    if vm.sendState == .idle { return }
                    if case .failed = vm.sendState { return }
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    private func makeHarness(foreground: Bool = false) throws -> Harness {
        let chat = StubChatService(script: [])
        let backgroundHandle = StubBackgroundHandle()
        let coordinator = BackgroundSessionCoordinator(factory: { backgroundHandle })
        let haptic = CountingHaptic()
        let notifications = RecordingNotificationCenter()
        let probe = StaticForegroundProbe(value: foreground)
        let feedback = CompletionFeedbackProvider(
            device: haptic,
            notifications: notifications,
            foregroundProbe: probe
        )

        let container = try AIChatModelContainer.inMemory()
        let persistence = ConversationPersistence(container: container)
        let connection = RelayConnectionMonitor()
        let pacer = StreamingTextPacer(
            configuration: .init(
                tickInterval: .milliseconds(5),
                baseCharsPerTick: 1024,
                maxCharsPerTick: 1024,
                backlogScale: 0
            )
        )
        let autoScroll = ConversationAutoScrollController()
        let transcription = TranscriptionService(api: RelayAPIClient(context: dummyRelayContext()))

        let initialThread = ConversationThread(title: "Initial")
        let vm = ConversationDetailViewModel(
            conversation: initialThread,
            chatService: chat,
            transcriptionService: transcription,
            persistence: persistence,
            connection: connection,
            pacer: pacer,
            autoScroll: autoScroll,
            backgroundSession: coordinator,
            feedback: feedback
        )
        return Harness(
            vm: vm,
            chat: chat,
            backgroundHandle: backgroundHandle,
            haptic: haptic,
            notifications: notifications
        )
    }

    private func dummyRelayContext() -> RelayRequestContext {
        RelayRequestContext(
            baseURL: URL(string: "http://127.0.0.1/")!,
            deviceID: "test",
            bearerToken: nil,
            allowsInsecureTLS: false
        )
    }
}

// MARK: - Test stubs

@MainActor
final class StubBackgroundHandle: BackgroundSessionHandle {
    var startCount = 0
    var invalidateCount = 0
    func start() { startCount += 1 }
    func invalidate() { invalidateCount += 1 }
}

final class CountingHaptic: HapticDevice, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var playSuccessCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func playSuccess() {
        lock.lock(); defer { lock.unlock() }
        _count += 1
    }
}

final class RecordingNotificationCenter: UserNotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _added: [UNNotificationRequest] = []
    var added: [UNNotificationRequest] {
        lock.lock(); defer { lock.unlock() }
        return _added
    }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws {
        lock.lock(); defer { lock.unlock() }
        _added.append(request)
    }
}

private struct StaticForegroundProbe: AppForegroundProbe {
    let value: Bool
    @MainActor var isForeground: Bool { value }
}

// MARK: - Fixture helpers

private extension ConversationThread {
    func with(_ mutate: (inout ConversationThread) -> Void) -> ConversationThread {
        var copy = self
        mutate(&copy)
        return copy
    }

    static func fixtureWithAssistantPlaceholder(text: String) -> ConversationThread {
        var thread = ConversationThread(title: "T")
        thread.messages.append(ChatMessage(role: .user, text: "ask"))
        thread.messages.append(ChatMessage(role: .assistant, text: text, status: .sent))
        return thread
    }
}
