//
//  RelayDashboardView.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/15.
//

import SwiftUI

struct RelayDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore

    @State private var showsSecrets = false
    @State private var page: RelayWorkspacePage = .overview
    @State private var consoleTab: RelayConsoleTab = .activity
    @State private var activityFilter = ""
    @State private var debugFilter = ""
    @State private var logSeverityFilter: RelayLogSeverityFilter = .all

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            dashboardBackground

            VStack(spacing: 20) {
                workspaceHeader
                    .padding(.horizontal, 32)
                    .padding(.top, 32)

                if page == .overview {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            heroCard
                            dashboardRow(leading: readinessCard, trailing: connectivityCard)
                            dashboardRow(leading: configurationCard, trailing: runtimeCard)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    }
                } else {
                    RelayConsoleWorkspaceView(controller: controller)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let feedback = controller.feedback {
                RelayFeedbackToast(feedback: feedback)
                    .padding(.top, 24)
                    .padding(.trailing, 24)
                    .onTapGesture {
                        controller.dismissFeedback()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.35, extraBounce: 0.06), value: controller.statusText)
        .animation(.snappy(duration: 0.35, extraBounce: 0.06), value: controller.feedback?.id)
        .animation(.snappy(duration: 0.35, extraBounce: 0.06), value: showsSecrets)
        .animation(.snappy(duration: 0.35, extraBounce: 0.06), value: page)
    }

    private var workspaceHeader: some View {
        RelayPanel {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace")
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Text("Switch between relay configuration and the dedicated console workspace.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Picker("Page", selection: $page) {
                    ForEach(RelayWorkspacePage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                statusBadge

                Button(action: controller.toggleServer) {
                    HStack(spacing: 10) {
                        if controller.isStarting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: controller.isRunning ? "stop.fill" : "play.fill")
                        }

                        Text(primaryActionTitle)
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryActionTint)
            }
        }
    }

    private var heroCard: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 18) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.09, green: 0.38, blue: 0.45),
                                                Color(red: 0.88, green: 0.55, blue: 0.25)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )

                                Image(systemName: "bolt.horizontal.circle.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 68, height: 68)
                            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 12)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("AIChat Relay")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))

                                Text("Production-grade local bridge for AIChat with secure secrets, guided setup, and live runtime diagnostics.")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.primary.opacity(0.72))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        WrapLayout(spacing: 10, lineSpacing: 10) {
                            statusBadge
                            RelayPill(icon: "lock.shield.fill", text: "Keychain-backed secrets", tint: Color(red: 0.08, green: 0.38, blue: 0.44))
                            RelayPill(icon: settings.allowNetworkClients ? "network" : "desktopcomputer", text: controller.activeBindingMode, tint: Color(red: 0.72, green: 0.43, blue: 0.19))

                            if settings.autoStartOnLaunch {
                                RelayPill(icon: "power.circle.fill", text: "Auto-start enabled", tint: Color(red: 0.16, green: 0.47, blue: 0.29))
                            }
                        }

                        Text(controller.statusMessage)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)

                        if let configurationIssue = controller.configurationIssue {
                            RelayInlineMessage(
                                icon: "exclamationmark.triangle.fill",
                                title: "Configuration Required",
                                message: configurationIssue,
                                tint: Color.orange
                            )
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 12) {
                        Button(action: controller.toggleServer) {
                            HStack(spacing: 10) {
                                if controller.isStarting {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                } else {
                                    Image(systemName: controller.isRunning ? "stop.fill" : "play.fill")
                                }

                                Text(primaryActionTitle)
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(minWidth: 180)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(primaryActionTint)

                        HStack(spacing: 10) {
                            Button("Copy Base URL") {
                                controller.copyToPasteboard(controller.recommendedClientBaseURL, label: "base URL")
                            }
                            .buttonStyle(.bordered)

                            Button("Open Health") {
                                controller.openHealthURL()
                            }
                            .buttonStyle(.bordered)
                            .disabled(settings.validatedPort == nil)
                        }
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    RelayMetricTile(title: "Setup Readiness", accent: Color(red: 0.08, green: 0.38, blue: 0.44)) {
                        Text("\(controller.completedSetupStepCount)/\(controller.setupSteps.count)")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("checks complete")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    RelayMetricTile(title: "Requests", accent: Color(red: 0.72, green: 0.43, blue: 0.19)) {
                        Text("\(controller.requestCount)")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(controller.lastRequestAt.map { "Last: \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No traffic yet")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    RelayMetricTile(title: "Success Rate", accent: Color(red: 0.16, green: 0.47, blue: 0.29)) {
                        Text(successRateText)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("\(controller.completedRequestCount) successful / \(controller.failedRequestCount) failed")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    RelayMetricTile(title: "Recommended Base URL", accent: Color(red: 0.41, green: 0.35, blue: 0.61)) {
                        Text(controller.recommendedClientBaseURL)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                        Text("Prefer this for AIChat client configuration.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var readinessCard: some View {
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

                Divider()
                    .overlay(relayDividerColor(colorScheme))

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: settings.allowNetworkClients ? "shared.with.you.circle.fill" : "wifi.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(settings.allowNetworkClients ? Color(red: 0.08, green: 0.38, blue: 0.44) : Color.orange)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.allowNetworkClients ? "LAN access is enabled." : "Localhost-only mode is enabled.")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Text(settings.allowNetworkClients
                             ? "macOS may request firewall permission the first time the listener binds to the network."
                             : "Use this mode when the client and relay both run on the same Mac.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var connectivityCard: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client Setup")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Copy a stable base URL and generated `xcconfig` values without leaving the dashboard.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Copy Snippet") {
                        controller.copyToPasteboard(controller.clientConfigurationSnippet, label: "xcconfig snippet")
                    }
                    .buttonStyle(.bordered)
                }

                if controller.endpoints.isEmpty {
                    RelayEmptyState(
                        symbol: "network.slash",
                        title: "No reachable endpoints yet",
                        message: "Choose a valid TCP port to generate connection details for clients."
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(controller.endpoints) { endpoint in
                            RelayEndpointRow(endpoint: endpoint) {
                                controller.copyToPasteboard(endpoint.urlString, label: "\(endpoint.title) URL")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended `Config/Secrets.xcconfig` values")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextEditor(text: .constant(controller.clientConfigurationSnippet))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 134)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(relayEditorBackground(colorScheme))
                        )
                        .foregroundStyle(relayEditorForeground(colorScheme))

                    HStack(spacing: 10) {
                        Button("Copy Health URL") {
                            controller.copyToPasteboard(controller.relayHealthURL, label: "health URL")
                        }
                        .buttonStyle(.bordered)

                        Button("Open Health") {
                            controller.openHealthURL()
                        }
                        .buttonStyle(.bordered)
                        .disabled(settings.validatedPort == nil)
                    }
                }
            }
        }
    }

    private var configurationCard: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Configuration")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Edit credentials, binding rules, and diagnostics in one place. Secrets are stored in the macOS Keychain.")
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
                    Text("Credentials")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Network")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

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

                VStack(alignment: .leading, spacing: 14) {
                    Text("Diagnostics")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

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

    private var runtimeCard: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Runtime")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Monitor listener state, request throughput, and the latest operational signals.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    RelayMetricTile(title: "Uptime", accent: statusColor) {
                        runtimeDurationView
                        Text(controller.startedAt == nil ? "Start the relay to begin accepting traffic." : "Running continuously since launch.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    RelayMetricTile(title: "Port", accent: Color(red: 0.72, green: 0.43, blue: 0.19)) {
                        Text(settings.validatedPort.map(String.init) ?? "Invalid")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(controller.activeBindingMode)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    RelayMetricTile(title: "Successful", accent: Color(red: 0.16, green: 0.47, blue: 0.29)) {
                        Text("\(controller.completedRequestCount)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(controller.lastRequestAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awaiting first request")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    RelayMetricTile(title: "Failed", accent: Color.red) {
                        Text("\(controller.failedRequestCount)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(controller.lastFailureAt.map { "Last failure \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No failed requests")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                RelayInlineMessage(
                    icon: "waveform.path.ecg",
                    title: "Health endpoint",
                    message: controller.relayHealthURL,
                    tint: Color(red: 0.08, green: 0.38, blue: 0.44)
                )

                if let lastFailureMessage = controller.lastFailureMessage {
                    RelayInlineMessage(
                        icon: "xmark.octagon.fill",
                        title: "Latest failure",
                        message: lastFailureMessage,
                        tint: Color.red
                    )
                }
            }
        }
    }

    private var consoleCard: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Console")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Review live activity logs or sanitized upstream payloads without switching tools.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("Console", selection: $consoleTab) {
                        ForEach(RelayConsoleTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                if consoleTab == .activity {
                    consoleControls(
                        filterText: $activityFilter,
                        placeholder: "Filter activity by level, path, or message",
                        trailingControls: {
                            Picker("Severity", selection: $logSeverityFilter) {
                                ForEach(RelayLogSeverityFilter.allCases) { filter in
                                    Text(filter.rawValue).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 310)

                            Button("Copy Visible") {
                                controller.copyToPasteboard(filteredActivityLogText, label: "visible activity log")
                            }
                            .buttonStyle(.bordered)
                            .disabled(filteredActivityEntries.isEmpty)

                            Button("Clear") {
                                controller.clearLogEntries()
                            }
                            .buttonStyle(.bordered)
                            .disabled(controller.logEntries.isEmpty)
                        }
                    )

                    if filteredActivityEntries.isEmpty {
                        RelayEmptyState(
                            symbol: activityFilter.isEmpty && controller.logEntries.isEmpty ? "text.badge.xmark" : "line.3.horizontal.decrease.circle",
                            title: activityFilter.isEmpty && controller.logEntries.isEmpty ? "No activity yet" : "No activity matches the current filter",
                            message: activityFilter.isEmpty && controller.logEntries.isEmpty
                                ? "Start the relay and send a request to populate operational events."
                                : "Adjust the search text or severity filter to broaden the result set."
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(filteredActivityEntries) { entry in
                                    RelayActivityRow(entry: entry)
                                }
                            }
                        }
                        .frame(minHeight: 260, maxHeight: 420)
                    }
                } else {
                    consoleControls(
                        filterText: $debugFilter,
                        placeholder: "Filter debug payloads by title or body",
                        trailingControls: {
                            Toggle("Capture Debug", isOn: $settings.debugLoggingEnabled)
                                .toggleStyle(.switch)
                                .fixedSize()

                            Button("Copy Visible") {
                                controller.copyToPasteboard(filteredDebugLogText, label: "visible debug log")
                            }
                            .buttonStyle(.bordered)
                            .disabled(filteredDebugEntries.isEmpty)

                            Button("Clear") {
                                controller.clearDebugEntries()
                            }
                            .buttonStyle(.bordered)
                            .disabled(controller.debugEntries.isEmpty)
                        }
                    )

                    if settings.debugLoggingEnabled == false {
                        RelayEmptyState(
                            symbol: "ladybug.slash",
                            title: "Debug capture is disabled",
                            message: "Enable debug capture to inspect sanitized client requests, upstream Gemini requests, and returned payloads.",
                            actionTitle: "Enable Debug Capture"
                        ) {
                            settings.debugLoggingEnabled = true
                        }
                    } else if filteredDebugEntries.isEmpty {
                        RelayEmptyState(
                            symbol: debugFilter.isEmpty ? "ladybug" : "line.3.horizontal.decrease.circle",
                            title: debugFilter.isEmpty ? "No debug traffic yet" : "No debug entries match the current filter",
                            message: debugFilter.isEmpty
                                ? "Send a request through the relay to populate this console."
                                : "Adjust the search text to broaden the result set."
                        )
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(filteredDebugEntries) { entry in
                                    RelayDebugRow(entry: entry) {
                                        controller.copyToPasteboard(entry.body, label: "debug entry")
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 280, maxHeight: 460)
                    }
                }
            }
        }
    }

    private var dashboardBackground: some View {
        ZStack {
            LinearGradient(
                colors: relayCanvasGradient(colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(relayCanvasAccent(colorScheme, warm: false))
                .frame(width: 540, height: 540)
                .blur(radius: 80)
                .offset(x: -280, y: -260)

            Circle()
                .fill(relayCanvasAccent(colorScheme, warm: true))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: 260, y: 220)
        }
    }

    private var statusBadge: some View {
        RelayPill(
            icon: statusSymbol,
            text: controller.statusText,
            tint: statusColor
        )
    }

    private var primaryActionTitle: String {
        if controller.isStarting {
            return "Starting Relay"
        }

        return controller.isRunning ? "Stop Relay" : "Start Relay"
    }

    private var primaryActionTint: Color {
        switch controller.status {
        case .running:
            return Color.red
        case .starting:
            return Color.orange
        case .failed:
            return Color.red
        case .stopped:
            return Color(red: 0.08, green: 0.38, blue: 0.44)
        }
    }

    private var successRateText: String {
        guard let successRate = controller.requestSuccessRate else {
            return "N/A"
        }

        return "\(Int((successRate * 100).rounded()))%"
    }

    @ViewBuilder
    private var runtimeDurationView: some View {
        if let startedAt = controller.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(formattedDuration(from: startedAt, now: context.date))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
            }
        } else {
            Text("Stopped")
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
    }

    private var filteredActivityEntries: [RelayLogEntry] {
        controller.logEntries
            .reversed()
            .filter { entry in
                switch logSeverityFilter {
                case .all:
                    break
                case .warningsAndErrors:
                    guard entry.level == .warning || entry.level == .error else {
                        return false
                    }
                case .errorsOnly:
                    guard entry.level == .error else {
                        return false
                    }
                }

                let normalizedFilter = activityFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedFilter.isEmpty == false else {
                    return true
                }

                let haystack = [
                    entry.level.rawValue,
                    entry.message,
                    entry.timestamp.formatted(date: .abbreviated, time: .standard)
                ]
                .joined(separator: " ")
                .localizedLowercase

                return haystack.contains(normalizedFilter.localizedLowercase)
            }
    }

    private var filteredDebugEntries: [RelayDebugEntry] {
        controller.debugEntries
            .reversed()
            .filter { entry in
                let normalizedFilter = debugFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalizedFilter.isEmpty == false else {
                    return true
                }

                let haystack = [entry.title, entry.body].joined(separator: " ").localizedLowercase
                return haystack.contains(normalizedFilter.localizedLowercase)
            }
    }

    private var filteredActivityLogText: String {
        filteredActivityEntries.map(activityText(for:)).joined(separator: "\n")
    }

    private var filteredDebugLogText: String {
        filteredDebugEntries.map(debugText(for:)).joined(separator: "\n\n")
    }

    private var statusColor: Color {
        switch controller.status {
        case .stopped:
            return Color.gray
        case .starting:
            return Color.orange
        case .running:
            return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .failed:
            return Color.red
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .stopped:
            return "pause.circle.fill"
        case .starting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .running:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    @ViewBuilder
    private func dashboardRow<Leading: View, Trailing: View>(
        leading: Leading,
        trailing: Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                leading
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                trailing
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(spacing: 20) {
                leading
                trailing
            }
        }
    }

    @ViewBuilder
    private func consoleControls<TrailingControls: View>(
        filterText: Binding<String>,
        placeholder: String,
        @ViewBuilder trailingControls: () -> TrailingControls
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                RelaySearchField(text: filterText, placeholder: placeholder)
                    .frame(maxWidth: .infinity)

                trailingControls()
            }

            VStack(alignment: .leading, spacing: 12) {
                RelaySearchField(text: filterText, placeholder: placeholder)
                trailingControls()
            }
        }
    }

    private func activityText(for entry: RelayLogEntry) -> String {
        "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.level.rawValue.uppercased()) \(entry.message)"
    }

    private func debugText(for entry: RelayDebugEntry) -> String {
        """
        [\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.title)
        \(entry.body)
        """
    }

    private func formattedDuration(from start: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%02dh %02dm", hours, minutes)
        }

        if minutes > 0 {
            return String(format: "%02dm %02ds", minutes, seconds)
        }

        return String(format: "%02ds", seconds)
    }

    private func maskedPreview(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "No value stored"
        }

        let suffixCount = min(6, trimmed.count)
        let suffix = trimmed.suffix(suffixCount)
        return "\(String(repeating: "•", count: max(6, trimmed.count - suffixCount)))\(suffix)"
    }
}

private enum RelayConsoleTab: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case debug = "Debug"

    var id: String { rawValue }
}

private enum RelayWorkspacePage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case console = "Console"

    var id: String { rawValue }
}

private enum RelayLogSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All Events"
    case warningsAndErrors = "Warnings + Errors"
    case errorsOnly = "Errors Only"

    var id: String { rawValue }
}

private struct RelayPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(relaySurfaceFill(colorScheme, style: .panel))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(relaySurfaceStroke(colorScheme, style: .panel), lineWidth: 1.1)
                    )
                    .shadow(color: relayShadowColor(colorScheme), radius: 20, x: 0, y: 14)
            )
    }
}

private struct RelayMetricTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let accent: Color
    let content: Content

    init(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(relaySurfaceStroke(colorScheme, style: .card), lineWidth: 1)
                )
        )
    }
}

private struct RelayPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .pill))
        )
    }
}

private struct RelayInlineMessage: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

private struct RelaySetupStepRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let step: RelaySetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(stepTint.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: stepSymbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stepTint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))

                    Text(stepStatusText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(stepTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(stepTint.opacity(0.12))
                        )
                }

                Text(step.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }

    private var stepTint: Color {
        switch step.status {
        case .complete:
            return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .pending:
            return Color.orange
        case .blocked:
            return Color.red
        }
    }

    private var stepSymbol: String {
        switch step.status {
        case .complete:
            return "checkmark"
        case .pending:
            return "ellipsis"
        case .blocked:
            return "exclamationmark"
        }
    }

    private var stepStatusText: String {
        switch step.status {
        case .complete:
            return "Ready"
        case .pending:
            return "Pending"
        case .blocked:
            return "Blocked"
        }
    }
}

private struct RelayEndpointRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let endpoint: RelayEndpoint
    let copyAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: endpoint.title == "LAN" ? "wifi" : "desktopcomputer")
                        .foregroundStyle(endpoint.title == "LAN" ? Color(red: 0.72, green: 0.43, blue: 0.19) : Color(red: 0.08, green: 0.38, blue: 0.44))

                    Text(endpoint.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(endpoint.urlString)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(endpoint.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Copy URL") {
                copyAction()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

private struct RelayFieldGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    let validation: String
    let validationTint: Color
    let content: Content

    init(
        title: String,
        detail: String,
        validation: String,
        validationTint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.validation = validation
        self.validationTint = validationTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(relaySurfaceFill(colorScheme, style: .field))
            )

            Text(validation)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(validationTint)
        }
    }
}

private struct RelayToggleTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .field))
        )
    }
}

private struct RelaySearchField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .field))
        )
    }
}

private struct RelayEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

private struct RelayActivityRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: RelayLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(levelTint)
                .frame(width: 11, height: 11)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(entry.level.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(levelTint)

                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(entry.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }

    private var levelTint: Color {
        switch entry.level {
        case .info:
            return Color.blue
        case .success:
            return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

private struct RelayDebugRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: RelayDebugEntry
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))

                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy") {
                    copyAction()
                }
                .buttonStyle(.bordered)
            }

            TextEditor(text: .constant(entry.body))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140, maxHeight: 210)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(relayEditorBackground(colorScheme))
                )
                .foregroundStyle(relayEditorForeground(colorScheme))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

private struct RelayFeedbackToast: View {
    @Environment(\.colorScheme) private var colorScheme
    let feedback: RelayActionFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(feedback.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .toast))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1.2)
                )
                .shadow(color: relayShadowColor(colorScheme, elevated: true), radius: 20, x: 0, y: 12)
        )
    }

    private var tint: Color {
        switch feedback.style {
        case .info:
            return Color.blue
        case .success:
            return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }

    private var iconName: String {
        switch feedback.style {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private enum RelaySurfaceStyle {
    case panel
    case card
    case field
    case pill
    case toast
}

private func relayCanvasGradient(_ colorScheme: ColorScheme) -> [Color] {
    switch colorScheme {
    case .dark:
        return [
            Color(red: 0.07, green: 0.09, blue: 0.12),
            Color(red: 0.12, green: 0.10, blue: 0.09)
        ]
    case .light:
        return [
            Color(red: 0.95, green: 0.97, blue: 0.98),
            Color(red: 0.98, green: 0.95, blue: 0.91)
        ]
    @unknown default:
        return [
            Color(red: 0.95, green: 0.97, blue: 0.98),
            Color(red: 0.98, green: 0.95, blue: 0.91)
        ]
    }
}

private func relayCanvasAccent(_ colorScheme: ColorScheme, warm: Bool) -> Color {
    switch colorScheme {
    case .dark:
        return warm
            ? Color(red: 0.67, green: 0.42, blue: 0.21).opacity(0.16)
            : Color(red: 0.19, green: 0.42, blue: 0.52).opacity(0.22)
    case .light:
        return warm
            ? Color(red: 0.87, green: 0.58, blue: 0.29).opacity(0.18)
            : Color(red: 0.27, green: 0.54, blue: 0.64).opacity(0.17)
    @unknown default:
        return warm
            ? Color(red: 0.87, green: 0.58, blue: 0.29).opacity(0.18)
            : Color(red: 0.27, green: 0.54, blue: 0.64).opacity(0.17)
    }
}

private func relaySurfaceFill(_ colorScheme: ColorScheme, style: RelaySurfaceStyle) -> Color {
    switch colorScheme {
    case .dark:
        switch style {
        case .panel:
            return Color.white.opacity(0.08)
        case .card:
            return Color.white.opacity(0.06)
        case .field:
            return Color.white.opacity(0.10)
        case .pill:
            return Color.white.opacity(0.12)
        case .toast:
            return Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.96)
        }
    case .light:
        switch style {
        case .panel:
            return Color.white.opacity(0.64)
        case .card:
            return Color.white.opacity(0.58)
        case .field:
            return Color.white.opacity(0.72)
        case .pill:
            return Color.white.opacity(0.86)
        case .toast:
            return Color.white.opacity(0.94)
        }
    @unknown default:
        return style == .toast ? Color.white.opacity(0.94) : Color.white.opacity(0.64)
    }
}

private func relaySurfaceStroke(_ colorScheme: ColorScheme, style: RelaySurfaceStyle) -> Color {
    switch colorScheme {
    case .dark:
        switch style {
        case .panel:
            return Color.white.opacity(0.12)
        case .card:
            return Color.white.opacity(0.10)
        case .field:
            return Color.white.opacity(0.12)
        case .pill:
            return Color.white.opacity(0.14)
        case .toast:
            return Color.white.opacity(0.12)
        }
    case .light:
        switch style {
        case .panel:
            return Color.white.opacity(0.72)
        case .card:
            return Color.white.opacity(0.55)
        case .field:
            return Color.white.opacity(0.68)
        case .pill:
            return Color.white.opacity(0.82)
        case .toast:
            return Color.white.opacity(0.82)
        }
    @unknown default:
        return Color.white.opacity(0.55)
    }
}

private func relayShadowColor(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
    switch colorScheme {
    case .dark:
        return Color.black.opacity(elevated ? 0.34 : 0.28)
    case .light:
        return Color.black.opacity(elevated ? 0.12 : 0.08)
    @unknown default:
        return Color.black.opacity(0.08)
    }
}

private func relayDividerColor(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.white.opacity(0.12)
    case .light:
        return Color.white.opacity(0.45)
    @unknown default:
        return Color.white.opacity(0.45)
    }
}

private func relayEditorBackground(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color.black.opacity(0.66)
    case .light:
        return Color.black.opacity(0.90)
    @unknown default:
        return Color.black.opacity(0.90)
    }
}

private func relayEditorForeground(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:
        return Color(red: 0.75, green: 0.95, blue: 0.80)
    case .light:
        return Color(red: 0.62, green: 0.94, blue: 0.74)
    @unknown default:
        return Color(red: 0.62, green: 0.94, blue: 0.74)
    }
}

private struct WrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > maxWidth, cursorX > 0 {
                maxLineWidth = max(maxLineWidth, cursorX - spacing)
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        maxLineWidth = max(maxLineWidth, cursorX - spacing)
        return CGSize(width: max(0, maxLineWidth), height: cursorY + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
