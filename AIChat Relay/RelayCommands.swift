//
//  RelayCommands.swift
//  AIChat Relay
//
//  Enterprise-grade macOS menu bar commands with full keyboard shortcut coverage.
//

import SwiftUI

// MARK: - App-level menu cleanup

struct RelayAppCommands: Commands {
    @FocusedValue(\.relayMenuState) private var menuState

    var body: some Commands {
        // Remove File > New Window (redundant with single-instance Window)
        CommandGroup(replacing: .newItem) { }

        // Remove Edit > Undo / Redo (irrelevant for a server management app)
        CommandGroup(replacing: .undoRedo) { }

        // Override Cmd+, to navigate to the in-app Settings page
        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") {
                menuState?.selectedItem.wrappedValue = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

// MARK: - Server menu

struct RelayServerCommands: Commands {
    @FocusedValue(\.relayMenuState) private var menuState

    var body: some Commands {
        CommandMenu("Server") {
            Button(serverToggleLabel) {
                menuState?.controller.toggleServer()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(menuState == nil || menuState?.controller.isStarting == true)

            Divider()

            Button("Open Health Endpoint") {
                menuState?.controller.openHealthURL()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(menuState?.controller.settings.validatedPort == nil)

            Button("Copy Base URL") {
                guard let controller = menuState?.controller else { return }
                controller.copyToPasteboard(controller.recommendedClientBaseURL, label: "base URL")
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Copy Client Snippet") {
                guard let controller = menuState?.controller else { return }
                controller.copyToPasteboard(controller.clientConfigurationSnippet, label: "xcconfig snippet")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Regenerate Token") {
                menuState?.controller.regenerateRelayToken()
            }

            Divider()

            Button("Refresh Billing") {
                guard let controller = menuState?.controller else { return }
                Task {
                    await controller.refreshBillingSnapshot()
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
        }
    }

    private var serverToggleLabel: String {
        guard let controller = menuState?.controller else { return "Start Relay" }
        if controller.isStarting { return "Starting\u{2026}" }
        return controller.isRunning ? "Stop Relay" : "Start Relay"
    }
}

// MARK: - Navigate menu (view switching)

struct RelayViewCommands: Commands {
    @FocusedValue(\.relayMenuState) private var menuState

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Dashboard") {
                menuState?.selectedItem.wrappedValue = .dashboard
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Connectivity") {
                menuState?.selectedItem.wrappedValue = .connectivity
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Billing") {
                menuState?.selectedItem.wrappedValue = .billing
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Settings") {
                menuState?.selectedItem.wrappedValue = .settings
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Console") {
                menuState?.selectedItem.wrappedValue = .console
            }
            .keyboardShortcut("5", modifiers: .command)

            Divider()

            Button(secretsToggleLabel) {
                guard let binding = menuState?.showsSecrets else { return }
                binding.wrappedValue.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }

    private var secretsToggleLabel: String {
        menuState?.showsSecrets.wrappedValue == true ? "Hide Secrets" : "Show Secrets"
    }
}

// MARK: - Console menu

struct RelayConsoleCommands: Commands {
    @FocusedValue(\.relayMenuState) private var menuState

    var body: some Commands {
        CommandMenu("Console") {
            Button("Clear Activity Log") {
                menuState?.controller.clearLogEntries()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(menuState?.controller.logEntries.isEmpty != false)

            Button("Clear Debug Records") {
                menuState?.controller.clearDebugEntries()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(menuState?.controller.debugEntries.isEmpty != false)

            Divider()

            Button(debugCaptureLabel) {
                guard let settings = menuState?.controller.settings else { return }
                settings.debugLoggingEnabled.toggle()
            }
            .keyboardShortcut("d", modifiers: .command)
        }
    }

    private var debugCaptureLabel: String {
        menuState?.controller.settings.debugLoggingEnabled == true
            ? "Disable Debug Capture"
            : "Enable Debug Capture"
    }
}
