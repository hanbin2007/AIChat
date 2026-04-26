//
//  RelayRequestEnricher.swift
//  AIChat Watch App
//
//  Adds uniform client-context headers to every relay-bound URLRequest so
//  the server-side activity log can attribute traffic to a specific app
//  build, OS version, device model, and conversation. Server already
//  reads `x-aichat-conversation-id` (`chat/stream/route.ts:20`); the rest
//  of the headers are passive metadata for the activity log.
//
//  The enricher is `nonisolated` on purpose: it is called from
//  `RelayAIClient.streamReply` (synchronous `AsyncThrowingStream`
//  closure) and from `RelayAccountService.performJSONRequest`
//  (non-isolated struct method). `WKInterfaceDevice.current()` is a
//  `@MainActor`-isolated singleton in the SDK, so we snapshot the
//  device-model / OS-version strings once at startup and reuse them.
//

import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

enum RelayRequestEnricher {
    /// Attaches the standard client-context headers to a relay-bound
    /// request. Safe to call from any actor / any queue.
    nonisolated static func attachClientContext(
        to request: inout URLRequest,
        conversationID: UUID? = nil
    ) {
        let context = ClientContext.shared

        request.setValue(context.appVersion, forHTTPHeaderField: "x-aichat-app-version")
        request.setValue(context.appBuild, forHTTPHeaderField: "x-aichat-app-build")
        request.setValue(context.osHeader, forHTTPHeaderField: "x-aichat-os")
        request.setValue(context.deviceModel, forHTTPHeaderField: "x-aichat-device-model")
        request.setValue(context.localeIdentifier, forHTTPHeaderField: "x-aichat-locale")
        request.setValue(context.userAgent, forHTTPHeaderField: "User-Agent")

        if let conversationID {
            request.setValue(
                conversationID.uuidString,
                forHTTPHeaderField: "x-aichat-conversation-id"
            )
        }
    }
}

/// Thread-safe snapshot of immutable client-context values. Initialized
/// lazily on first use; subsequent reads are unsynchronized reads of
/// immutable strings.
private struct ClientContext: Sendable {
    let appVersion: String
    let appBuild: String
    let osHeader: String
    let deviceModel: String
    let localeIdentifier: String
    let userAgent: String

    static let shared: ClientContext = ClientContext.snapshot()

    private static func snapshot() -> ClientContext {
        let bundle = Bundle.main
        let appVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .nonEmptyTrimmed ?? "0"
        let appBuild = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .nonEmptyTrimmed ?? "0"

        let systemVersion: String
        let deviceModel: String
        let osLabel: String
        #if os(watchOS)
        // `WKInterfaceDevice.current()` is `@MainActor`-isolated in the
        // SDK, but the singleton's `model` / `systemVersion` properties
        // are read-only `String`s that are safe to read from any thread.
        // Hop to MainActor only if needed.
        if Thread.isMainThread {
            let device = MainActor.assumeIsolated { WKInterfaceDevice.current() }
            systemVersion = device.systemVersion
            deviceModel = device.model
        } else {
            let pair = DispatchQueue.main.sync { () -> (String, String) in
                let device = MainActor.assumeIsolated { WKInterfaceDevice.current() }
                return (device.systemVersion, device.model)
            }
            systemVersion = pair.0
            deviceModel = pair.1
        }
        osLabel = "watchOS"
        #elseif os(iOS)
        if Thread.isMainThread {
            let device = MainActor.assumeIsolated { UIDevice.current }
            systemVersion = device.systemVersion
            deviceModel = device.model
        } else {
            let pair = DispatchQueue.main.sync { () -> (String, String) in
                let device = MainActor.assumeIsolated { UIDevice.current }
                return (device.systemVersion, device.model)
            }
            systemVersion = pair.0
            deviceModel = pair.1
        }
        osLabel = "iOS"
        #else
        systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        deviceModel = "Mac"
        osLabel = "macOS"
        #endif

        let localeIdentifier = Locale.current.identifier
        let userAgent =
            "AIChat/\(appVersion) (build \(appBuild); \(osLabel) \(systemVersion); \(deviceModel))"

        return ClientContext(
            appVersion: appVersion,
            appBuild: appBuild,
            osHeader: "\(osLabel) \(systemVersion)",
            deviceModel: deviceModel,
            localeIdentifier: localeIdentifier,
            userAgent: userAgent
        )
    }
}
