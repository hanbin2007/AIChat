//
//  WatchDeviceIdentity.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

nonisolated struct CompanionDeviceIdentity: Equatable, Sendable {
    let rawIdentifier: String
    let deviceToken: UInt64
    let displayToken: String
}

nonisolated enum CompanionDeviceIdentityProvider {
    private static let fallbackIdentifierKey = "device_activation_fallback_identifier"

    @MainActor
    static func current(defaults: UserDefaults = .standard) -> CompanionDeviceIdentity {
        let rawIdentifier = currentVendorIdentifier() ?? storedFallbackIdentifier(defaults: defaults)
        let deviceToken = OfflineActivation.deviceToken(for: rawIdentifier)

        return CompanionDeviceIdentity(
            rawIdentifier: rawIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )
    }

    @MainActor
    private static func currentVendorIdentifier() -> String? {
        #if os(watchOS)
        return WKInterfaceDevice.current().identifierForVendor?.uuidString
        #elseif os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
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

typealias WatchDeviceIdentity = CompanionDeviceIdentity
typealias WatchDeviceIdentityProvider = CompanionDeviceIdentityProvider
