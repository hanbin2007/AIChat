//
//  AIChatRelayApp.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

@main
struct AIChatRelayApp: App {
    @StateObject private var controller = RelayServerController()

    var body: some Scene {
        WindowGroup {
            RelayDashboardView(controller: controller)
                .frame(minWidth: 980, minHeight: 760)
                .task {
                    controller.handleInitialLaunch()
                }
        }
        .windowResizability(.contentSize)
    }
}
