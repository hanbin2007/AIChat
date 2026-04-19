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
        Window("AIChat Relay", id: "relay-dashboard") {
            RelayDashboardView(controller: controller)
                .frame(minWidth: 1120, minHeight: 860)
                .task {
                    controller.handleInitialLaunch()
                }
        }
        .defaultSize(width: 1320, height: 920)
        .windowResizability(.contentMinSize)
        .commands {
            RelayAppCommands()
            RelayServerCommands()
            RelayViewCommands()
            RelayConsoleCommands()
        }
    }
}
