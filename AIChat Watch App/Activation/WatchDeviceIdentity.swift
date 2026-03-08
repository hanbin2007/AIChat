//
//  WatchDeviceIdentity.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import WatchKit

nonisolated struct WatchDeviceIdentity: Equatable, Sendable {
    let rawIdentifier: String
    let deviceToken: UInt64
    let displayToken: String
}

nonisolated enum WatchDeviceIdentityProvider {
    private static let fallbackIdentifierKey = "watch_activation_fallback_identifier"

    static func current(defaults: UserDefaults = .standard) -> WatchDeviceIdentity {
        let rawIdentifier =
            WKInterfaceDevice.current().identifierForVendor?.uuidString ??
            storedFallbackIdentifier(defaults: defaults)
        let deviceToken = OfflineActivation.deviceToken(for: rawIdentifier)

        return WatchDeviceIdentity(
            rawIdentifier: rawIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )
    }

    private static func storedFallbackIdentifier(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: fallbackIdentifierKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           existing.isEmpty == false {
            return existing
        }

        let generated = UUID().uuidString.uppercased()
        defaults.set(generated, forKey: fallbackIdentifierKey)
        return generated
    }
}
