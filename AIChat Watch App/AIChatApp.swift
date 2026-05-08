//
//  AIChatApp.swift
//  AIChat Watch App
//
//  `@main` entry — constructs the `AppEnvironment` composition root and
//  hands it to `RootView`, which owns the NavigationStack and renders
//  the full UI tree on top of the existing ViewModel layer.
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
            RootView()
                .environment(\.appEnvironment, environment)
                .task {
                    // Lazily ask once for notification permission so the
                    // turn-completion notify path has a chance to fire
                    // when the watch is backgrounded mid-stream.
                    await environment.completionFeedback.ensureNotificationAuthorization()
                }
        }
    }
}
#endif
