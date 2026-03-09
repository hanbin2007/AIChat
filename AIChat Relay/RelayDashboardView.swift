//
//  RelayDashboardView.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct RelayDashboardView: View {
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore
    @State private var showsSecrets = false

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.97, blue: 0.99),
                    Color(red: 0.99, green: 0.96, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsRow

                    HStack(alignment: .top, spacing: 20) {
                        configurationCard
                        connectivityCard
                    }

                    activityCard
                    debugCard
                }
                .padding(28)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AIChat Relay")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("A native macOS relay with a built-in UI, local HTTP server, and Gemini SSE bridging.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statusPill

            Button(action: controller.toggleServer) {
                Text(controller.isRunning || controller.isStarting ? "Stop Relay" : "Start Relay")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .background(cardBackground)
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statCard(title: "Mode", value: settings.allowNetworkClients ? "LAN + Localhost" : "Localhost only")
            statCard(title: "Requests", value: "\(controller.requestCount)")
            statCard(
                title: "Last Request",
                value: controller.lastRequestAt.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "No traffic yet"
            )
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Configuration")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer()

                Toggle("Show values", isOn: $showsSecrets)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            LabeledContent("Gemini API Key") {
                if showsSecrets {
                    TextField("AIza...", text: $settings.geminiAPIKey, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("AIza...", text: $settings.geminiAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
            }

            LabeledContent("Relay Token") {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if showsSecrets {
                            TextField("Bearer token", text: $settings.relayBearerToken)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Bearer token", text: $settings.relayBearerToken)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Regenerate") {
                            controller.regenerateRelayToken()
                        }
                        .buttonStyle(.bordered)

                        Button("Copy Token") {
                            controller.copyToPasteboard(
                                settings.runtimeConfiguration.relayBearerToken,
                                label: "relay token"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(spacing: 16) {
                LabeledContent("Port") {
                    TextField("8787", text: $settings.portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .disabled(controller.isRunning)
                }

                Toggle("Allow LAN devices", isOn: $settings.allowNetworkClients)
                    .disabled(controller.isRunning)
            }

            Toggle("Start relay when the app launches", isOn: $settings.autoStartOnLaunch)
            Toggle("Capture request/response debug logs", isOn: $settings.debugLoggingEnabled)

            if let configurationIssue = controller.configurationIssue {
                Label(configurationIssue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange)
            } else if settings.allowNetworkClients {
                Label("The first launch may trigger a macOS firewall prompt. Allow incoming connections for LAN access.", systemImage: "network")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var connectivityCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Client Setup")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(controller.endpoints) { endpoint in
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(endpoint.title)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(endpoint.urlString)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))

                            Text(endpoint.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Copy URL") {
                            controller.copyToPasteboard(endpoint.urlString, label: "\(endpoint.title) URL")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended `Config/Secrets.xcconfig` values")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextEditor(text: .constant(controller.clientConfigurationSnippet))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.85))
                    )
                    .foregroundStyle(Color.green.opacity(0.95))

                HStack(spacing: 10) {
                    Button("Copy Snippet") {
                        controller.copyToPasteboard(controller.clientConfigurationSnippet, label: "xcconfig snippet")
                    }
                    .buttonStyle(.bordered)

                    Button("Copy Health URL") {
                        controller.copyToPasteboard(controller.relayHealthURL, label: "health URL")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Activity")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer()

                Button("Copy Log") {
                    let logText = controller.logEntries
                        .map { entry in
                            "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.level.rawValue.uppercased()) \(entry.message)"
                        }
                        .joined(separator: "\n")
                    controller.copyToPasteboard(logText, label: "relay log")
                }
                .buttonStyle(.bordered)
            }

            Text(controller.statusMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.logEntries) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(color(for: entry.level))
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.level.rawValue.uppercased())
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(color(for: entry.level))

                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Text(entry.message)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.72))
                        )
                    }
                }
            }
            .frame(minHeight: 240)
        }
        .padding(24)
        .background(cardBackground)
    }

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Debug")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer()

                Button("Clear") {
                    controller.clearDebugEntries()
                }
                .buttonStyle(.bordered)
                .disabled(controller.debugEntries.isEmpty)
            }

            if settings.debugLoggingEnabled == false {
                Text("Enable debug capture to inspect client requests, Gemini upstream requests, and returned payloads.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if controller.debugEntries.isEmpty {
                Text("No debug traffic yet. Send a request through the relay to populate this view.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(controller.debugEntries.reversed())) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.system(size: 13, weight: .bold, design: .rounded))

                                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button("Copy") {
                                        controller.copyToPasteboard(entry.body, label: "debug entry")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                TextEditor(text: .constant(entry.body))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 140, maxHeight: 200)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.black.opacity(0.88))
                                    )
                                    .foregroundStyle(Color.green.opacity(0.94))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.72))
                            )
                        }
                    }
                }
                .frame(minHeight: 280)
            }
        }
        .padding(24)
        .background(cardBackground)
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(controller.statusText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(cardBackground)
    }

    private func color(for level: RelayLogLevel) -> Color {
        switch level {
        case .info:
            return Color.blue
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .stopped:
            return Color.gray
        case .starting:
            return Color.orange
        case .running:
            return Color.green
        case .failed:
            return Color.red
        }
    }

    private var cardBackground: some ShapeStyle {
        .ultraThinMaterial
    }
}
