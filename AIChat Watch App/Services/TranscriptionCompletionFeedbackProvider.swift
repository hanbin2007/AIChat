import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

enum CompletionFeedbackEvent: Equatable {
    case transcriptionCompleted
    case assistantReplyCompleted

    static let notificationIdentifiers: Set<String> = [
        CompletionFeedbackEvent.transcriptionCompleted.notificationIdentifier,
        CompletionFeedbackEvent.assistantReplyCompleted.notificationIdentifier
    ]

    static func foregroundPresentationOptions(
        forNotificationIdentifier identifier: String
    ) -> UNNotificationPresentationOptions {
        guard notificationIdentifiers.contains(identifier) else {
            return []
        }

        return [.sound]
    }

    var notificationIdentifier: String {
        switch self {
        case .transcriptionCompleted:
            return "transcription-complete-feedback"
        case .assistantReplyCompleted:
            return "assistant-reply-complete-feedback"
        }
    }

    var titleLocalizationKey: String {
        switch self {
        case .transcriptionCompleted:
            return "transcription.feedback.title"
        case .assistantReplyCompleted:
            return "assistant_reply.feedback.title"
        }
    }

    var bodyLocalizationKey: String {
        switch self {
        case .transcriptionCompleted:
            return "transcription.feedback.body"
        case .assistantReplyCompleted:
            return "assistant_reply.feedback.body"
        }
    }

    var triggersForegroundFeedback: Bool {
        switch self {
        case .transcriptionCompleted:
            return true
        case .assistantReplyCompleted:
            return false
        }
    }
}

private final class CompletionFeedbackNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionFeedbackNotificationDelegate()

    private override init() {}

    func install(on notificationCenter: UNUserNotificationCenter) {
        notificationCenter.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        CompletionFeedbackEvent.foregroundPresentationOptions(
            forNotificationIdentifier: notification.request.identifier
        )
    }
}

@MainActor
protocol CompletionFeedbackProviding {
    func prepareForPossibleBackgroundFeedback() async
    func notifyCompletion(of event: CompletionFeedbackEvent) async
}

struct NoopCompletionFeedbackProvider: CompletionFeedbackProviding {
    func prepareForPossibleBackgroundFeedback() async {}
    func notifyCompletion(of event: CompletionFeedbackEvent) async {}
}

@MainActor
final class DeviceCompletionFeedbackProvider: CompletionFeedbackProviding {
    private let requestDelay: TimeInterval = 0.2
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        CompletionFeedbackNotificationDelegate.shared.install(on: notificationCenter)
    }

    func prepareForPossibleBackgroundFeedback() async {
        guard canDeliverForegroundFeedback else {
            return
        }

        _ = await ensureBackgroundNotificationAuthorization()
    }

    func notifyCompletion(of event: CompletionFeedbackEvent) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [event.notificationIdentifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [event.notificationIdentifier])

        if canDeliverForegroundFeedback {
            guard event.triggersForegroundFeedback else {
                return
            }

            triggerForegroundFeedback()
            return
        }

        let didScheduleNotification = await scheduleCompletionNotification(for: event)
        if didScheduleNotification == false, event.triggersForegroundFeedback {
            triggerForegroundFeedback()
        }
    }

    private var canDeliverForegroundFeedback: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #elseif os(watchOS)
        WKExtension.shared().applicationState == .active &&
        WatchDisplayStateMonitor.shared.isLuminanceReduced == false
        #else
        true
        #endif
    }

    private func triggerForegroundFeedback() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    private func scheduleCompletionNotification(for event: CompletionFeedbackEvent) async -> Bool {
        guard await ensureBackgroundNotificationAuthorization() else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.tr(event.titleLocalizationKey)
        content.body = L10n.tr(event.bodyLocalizationKey)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: requestDelay,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: event.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            return false
        }
    }

    private func ensureBackgroundNotificationAuthorization() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }
}
