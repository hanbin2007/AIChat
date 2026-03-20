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
    @MainActor
    static func current(
        activationRepository: ActivationRepository? = nil,
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> CompanionDeviceIdentity {
        let repository = activationRepository ??
            ActivationRepository(configuration: configuration, rootURL: rootURL, fileManager: fileManager)
        let rawIdentifier = currentVendorIdentifier() ?? repository.loadOrCreateFallbackIdentifier()
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
}

typealias WatchDeviceIdentity = CompanionDeviceIdentity
typealias WatchDeviceIdentityProvider = CompanionDeviceIdentityProvider
