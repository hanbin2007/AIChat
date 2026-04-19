//
//  RelaySettingsPage.swift
//  AIChat Relay
//
//  In-app settings page — credentials, network, preferences, and readiness checklist.
//

import SwiftUI

struct RelaySettingsPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore
    @State private var showsSecrets = false

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                readinessSection
                credentialsSection
                networkSection
                preferencesSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Readiness

    private var readinessSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Launch Checklist")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Bring the relay online with explicit, supportable defaults before connecting clients.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(controller.completedSetupStepCount)/\(controller.setupSteps.count)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        Text("steps ready")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    ForEach(controller.setupSteps) { step in
                        RelaySetupStepRow(step: step)
                    }
                }
            }
        }
    }

    // MARK: - Credentials

    private var credentialsSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Credentials")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Secrets are stored securely in the macOS Keychain.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(showsSecrets ? "Hide Values" : "Reveal Values") {
                        showsSecrets.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 14) {
                    RelayFieldGroup(
                        title: "Gemini API Key",
                        detail: settings.geminiAPIKey.isEmpty
                            ? "Required before the relay can start."
                            : "Stored securely and redacted in debug output.",
                        validation: settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Missing API key." : "Ready",
                        validationTint: settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.green
                    ) {
                        Group {
                            if showsSecrets {
                                TextField("AIza...", text: $settings.geminiAPIKey, axis: .vertical)
                            } else {
                                SecureField("AIza...", text: $settings.geminiAPIKey)
                            }
                        }
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)

                        if showsSecrets == false, settings.geminiAPIKey.isEmpty == false {
                            Text(maskedPreview(for: settings.geminiAPIKey))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    RelayFieldGroup(
                        title: "Relay Token",
                        detail: settings.relayBearerToken.isEmpty
                            ? "Required for client authorization."
                            : "Issued token will be embedded into the generated snippet.",
                        validation: settings.relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Missing relay token." : "Ready",
                        validationTint: settings.relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.green
                    ) {
                        Group {
                            if showsSecrets {
                                TextField("Bearer token", text: $settings.relayBearerToken)
                            } else {
                                SecureField("Bearer token", text: $settings.relayBearerToken)
                            }
                        }
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)

                        if showsSecrets == false, settings.relayBearerToken.isEmpty == false {
                            Text(maskedPreview(for: settings.relayBearerToken))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Regenerate") {
                                controller.regenerateRelayToken()
                            }
                            .buttonStyle(.bordered)

                            Button("Copy Token") {
                                controller.copyToPasteboard(settings.runtimeConfiguration.relayBearerToken, label: "relay token")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Network

    private var networkSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Network")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text("Configure the relay listener binding. Changes require a restart.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    RelayFieldGroup(
                        title: "Port",
                        detail: controller.isRunning || controller.isStarting
                            ? "Stop the relay before changing the listener port."
                            : "Choose a stable port for desktop and device clients.",
                        validation: settings.validatedPort == nil ? "Invalid TCP port." : "Ready",
                        validationTint: settings.validatedPort == nil ? Color.red : Color.green
                    ) {
                        TextField("8787", text: $settings.portText)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .textFieldStyle(.plain)
                            .disabled(controller.isRunning || controller.isStarting)
                    }

                    RelayToggleTile(
                        title: "Allow LAN devices",
                        detail: "Enable iPhone and Apple Watch clients on the same network.",
                        isOn: $settings.allowNetworkClients
                    )
                    .disabled(controller.isRunning || controller.isStarting)

                    if controller.isRunning || controller.isStarting {
                        Text("Listener binding is locked while the relay is active.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferences")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text("Startup behavior and diagnostic capture settings.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    RelayToggleTile(
                        title: "Start relay at launch",
                        detail: "Bring the relay online automatically when the app opens.",
                        isOn: $settings.autoStartOnLaunch
                    )

                    RelayToggleTile(
                        title: "Capture debug payloads",
                        detail: "Record sanitized client and Gemini payloads for troubleshooting.",
                        isOn: $settings.debugLoggingEnabled
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func maskedPreview(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "No value stored" }
        let suffixCount = min(6, trimmed.count)
        let suffix = trimmed.suffix(suffixCount)
        return "\(String(repeating: "\u{2022}", count: max(6, trimmed.count - suffixCount)))\(suffix)"
    }
}
