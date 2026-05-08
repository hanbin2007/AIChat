//
//  CompletionFeedbackProvider.swift
//  AIChat Watch App
//
//  When a streaming reply finishes successfully, the watch should
//  - play the system success haptic, and
//  - if the app is currently backgrounded, post a local notification
//    so the user gets nudged back without unlocking.
//
//  All three side effects are factored behind protocols so tests
//  inject in-memory stubs; the production wiring binds them to
//  WKInterfaceDevice / UNUserNotificationCenter / WKApplication.
//

import Foundation
#if os(watchOS)
import WatchKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

protocol HapticDevice: Sendable {
    func playSuccess()
}

protocol UserNotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

protocol AppForegroundProbe: Sendable {
    @MainActor var isForeground: Bool { get }
}

@MainActor
final class CompletionFeedbackProvider {

    private let device: HapticDevice
    private let notifications: UserNotificationCenterProtocol
    private let foregroundProbe: AppForegroundProbe
    private var didRequestAuthorization = false

    init(
        device: HapticDevice,
        notifications: UserNotificationCenterProtocol,
        foregroundProbe: AppForegroundProbe
    ) {
        self.device = device
        self.notifications = notifications
        self.foregroundProbe = foregroundProbe
    }

    /// Convenience init wiring the production implementations.
    static func makeDefault() -> CompletionFeedbackProvider {
        CompletionFeedbackProvider(
            device: SystemHapticDevice(),
            notifications: SystemUserNotificationCenter(),
            foregroundProbe: SystemAppForegroundProbe()
        )
    }

    /// Always plays — VM calls this only on the success path.
    func playSuccess() {
        device.playSuccess()
    }

    /// Posts a local notification iff the app is not currently in the
    /// foreground; otherwise no-op (avoid double-buzzing the user
    /// who's already looking at the screen).
    func notifyTurnComplete(conversationTitle: String, preview: String) async {
        guard !foregroundProbe.isForeground else { return }
        let trimmedPreview = String(preview.prefix(80))
        let content = UNMutableNotificationContent()
        content.title = conversationTitle
        content.body = trimmedPreview
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        try? await notifications.add(request)
    }

    /// Idempotent — first call asks the system once. We don't observe
    /// the result; the request flow is best-effort and silent on
    /// denial, since the haptic still works and the user can grant
    /// permission later in Settings.
    func ensureNotificationAuthorization() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
    }
}

// MARK: - Production wirings

private struct SystemHapticDevice: HapticDevice {
    func playSuccess() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }
}

private struct SystemUserNotificationCenter: UserNotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

private struct SystemAppForegroundProbe: AppForegroundProbe {
    @MainActor var isForeground: Bool {
        #if os(watchOS)
        return WKApplication.shared().applicationState == .active
        #else
        return true
        #endif
    }
}
