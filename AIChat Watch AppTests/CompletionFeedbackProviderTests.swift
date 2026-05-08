//
//  CompletionFeedbackProviderTests.swift
//  AIChat Watch AppTests
//
//  Pins the §2.3 / §2.6 completion feedback rules:
//    - playSuccess always forwards to the haptic device
//    - notifyTurnComplete only posts when the app is backgrounded
//    - notifyTurnComplete trims preview to 80 chars
//    - ensureNotificationAuthorization asks once and swallows errors
//

import XCTest
import UserNotifications
@testable import AIChat_Watch_App

@MainActor
final class CompletionFeedbackProviderTests: XCTestCase {

    func test_playSuccessForwardsToHapticDevice() async throws {
        let device = StubHapticDevice()
        let center = StubNotificationCenter()
        let probe = StubForegroundProbe(isForeground: true)
        let provider = CompletionFeedbackProvider(device: device, notifications: center, foregroundProbe: probe)

        provider.playSuccess()
        XCTAssertEqual(device.playSuccessCount, 1)
    }

    func test_notifyTurnComplete_skippedWhenForeground() async throws {
        let center = StubNotificationCenter()
        let provider = CompletionFeedbackProvider(
            device: StubHapticDevice(),
            notifications: center,
            foregroundProbe: StubForegroundProbe(isForeground: true)
        )

        await provider.notifyTurnComplete(conversationTitle: "T", preview: "P")
        XCTAssertEqual(center.added.count, 0)
    }

    func test_notifyTurnComplete_addsRequestWhenBackgrounded() async throws {
        let center = StubNotificationCenter()
        let provider = CompletionFeedbackProvider(
            device: StubHapticDevice(),
            notifications: center,
            foregroundProbe: StubForegroundProbe(isForeground: false)
        )

        await provider.notifyTurnComplete(conversationTitle: "Title", preview: "Body")
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(center.added.first?.content.title, "Title")
        XCTAssertEqual(center.added.first?.content.body, "Body")
    }

    func test_notifyTurnComplete_truncatesPreviewTo80Chars() async throws {
        let center = StubNotificationCenter()
        let provider = CompletionFeedbackProvider(
            device: StubHapticDevice(),
            notifications: center,
            foregroundProbe: StubForegroundProbe(isForeground: false)
        )

        let long = String(repeating: "x", count: 200)
        await provider.notifyTurnComplete(conversationTitle: "T", preview: long)
        XCTAssertEqual(center.added.first?.content.body.count, 80)
    }

    func test_ensureAuthorization_onlyAsksOnce() async throws {
        let center = StubNotificationCenter()
        center.authorizationResult = .success(true)
        let provider = CompletionFeedbackProvider(
            device: StubHapticDevice(),
            notifications: center,
            foregroundProbe: StubForegroundProbe(isForeground: true)
        )

        await provider.ensureNotificationAuthorization()
        await provider.ensureNotificationAuthorization()
        await provider.ensureNotificationAuthorization()
        XCTAssertEqual(center.authorizationCallCount, 1)
    }

    func test_ensureAuthorization_swallowsErrorAndDeniedResult() async throws {
        let center = StubNotificationCenter()
        center.authorizationResult = .failure(StubError.boom)
        let provider = CompletionFeedbackProvider(
            device: StubHapticDevice(),
            notifications: center,
            foregroundProbe: StubForegroundProbe(isForeground: true)
        )

        await provider.ensureNotificationAuthorization()
        // No throw, no crash. Subsequent calls still no-op.
        await provider.ensureNotificationAuthorization()
        XCTAssertEqual(center.authorizationCallCount, 1)
    }
}

// MARK: - Stubs

private final class StubHapticDevice: HapticDevice, @unchecked Sendable {
    private let lock = NSLock()
    private var _playSuccessCount = 0
    var playSuccessCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _playSuccessCount
    }
    func playSuccess() {
        lock.lock(); defer { lock.unlock() }
        _playSuccessCount += 1
    }
}

private final class StubNotificationCenter: UserNotificationCenterProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _added: [UNNotificationRequest] = []
    private var _authorizationCallCount = 0
    var authorizationResult: Result<Bool, Error> = .success(true)

    var added: [UNNotificationRequest] {
        lock.lock(); defer { lock.unlock() }
        return _added
    }

    var authorizationCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _authorizationCallCount
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.lock()
        _authorizationCallCount += 1
        let result = authorizationResult
        lock.unlock()
        switch result {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.lock(); defer { lock.unlock() }
        _added.append(request)
    }
}

private struct StubForegroundProbe: AppForegroundProbe {
    let _isForeground: Bool
    init(isForeground: Bool) { self._isForeground = isForeground }
    @MainActor var isForeground: Bool { _isForeground }
}
