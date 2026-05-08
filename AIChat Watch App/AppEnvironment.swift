//
//  AppEnvironment.swift
//  AIChat Watch App
//
//  Composition root for the rewritten Watch backend. Owns the
//  `RelayAPIClient` actor and the domain services that each ViewModel
//  depends on. Constructed once at app launch from `AppConfiguration`
//  and the device identity, then injected into the SwiftUI view tree
//  via `.environment`.
//
//  Strict MVVM: `AppEnvironment` does NOT hold ViewModels. Views
//  construct their own VMs from the injected services. This keeps
//  cross-screen state out of the composition root.
//
//  Phase 1A status: nothing in the existing app reads from
//  `AppEnvironment` yet. The legacy `ChatStore` keeps powering
//  `ContentView`. This file lays the wiring so subsequent phases can
//  migrate one screen at a time.
//

import Foundation
import SwiftUI

@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let deviceIdentity: WatchDeviceIdentity
    let relayAPI: RelayAPIClient?
    let billingService: RelayBillingService?
    let activationService: RelayActivationService?

    init(
        configuration: AppConfiguration,
        deviceIdentity: WatchDeviceIdentity
    ) {
        self.configuration = configuration
        self.deviceIdentity = deviceIdentity

        if let context = Self.makeRequestContext(
            configuration: configuration,
            deviceID: deviceIdentity.rawIdentifier
        ) {
            let client = RelayAPIClient(context: context)
            self.relayAPI = client
            self.billingService = RelayBillingService(
                networking: client,
                deviceIdentity: deviceIdentity
            )
            self.activationService = RelayActivationService(
                networking: client,
                deviceIdentity: deviceIdentity
            )
        } else {
            self.relayAPI = nil
            self.billingService = nil
            self.activationService = nil
        }
    }

    /// Construct a `RelayRequestContext` from `AppConfiguration` if the
    /// relay base URL is configured. Bearer token may be `nil` at
    /// bootstrap time — the activation flow obtains it on first call.
    static func makeRequestContext(
        configuration: AppConfiguration,
        deviceID: String
    ) -> RelayRequestContext? {
        guard let baseURL = configuration.relayBaseURL else {
            return nil
        }
        return RelayRequestContext(
            baseURL: baseURL,
            deviceID: deviceID,
            bearerToken: configuration.resolvedRelayBearerToken,
            allowsInsecureTLS: configuration.relayAllowsInsecureTLS
        )
    }
}

// MARK: - SwiftUI environment plumbing

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
