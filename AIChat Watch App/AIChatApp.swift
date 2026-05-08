//
//  AIChatApp.swift
//  AIChat Watch App
//
//  `@main` entry — constructs the `AppEnvironment` composition root and
//  hands it to a `PlaceholderShell` view. UI/UX is intentionally
//  minimal: the rewrite focuses on the backend + ViewModel layers; the
//  full design overhaul ships in a follow-up phase that consumes the
//  same ViewModels.
//

import Foundation
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

#if os(watchOS)
@main
struct AIChat_Watch_AppApp: App {
    @State private var environment: AppEnvironment

    init() {
        let configuration = AppConfiguration.load()
        let deviceIdentity = MainActor.assumeIsolated {
            WatchDeviceIdentityProvider.current(configuration: configuration)
        }
        _environment = State(initialValue: AppEnvironment(
            configuration: configuration,
            deviceIdentity: deviceIdentity
        ))
    }

    var body: some Scene {
        WindowGroup {
            PlaceholderShell()
                .environment(\.appEnvironment, environment)
        }
    }
}
#endif
