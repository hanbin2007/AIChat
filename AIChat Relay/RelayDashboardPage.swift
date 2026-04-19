//
//  RelayDashboardPage.swift
//  AIChat Relay
//
//  Dashboard overview page — key metrics, runtime stats, and quick actions.
//

import SwiftUI

struct RelayDashboardPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroSection
                metricsGrid
                runtimeSection

                if let configurationIssue = controller.configurationIssue {
                    RelayInlineMessage(
                        icon: "exclamationmark.triangle.fill",
                        title: "Configuration Required",
                        message: configurationIssue,
                        tint: Color.orange
                    )
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero section

    private var heroSection: some View {
        RelayPanel {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.09, green: 0.38, blue: 0.45),
                                            Color(red: 0.88, green: 0.55, blue: 0.25),
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

                            Text("Production-grade local bridge with secure secrets, guided setup, and live runtime diagnostics.")
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
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 12) {
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
        }
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
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

            RelayMetricTile(title: "Managed Accounts", accent: Color(red: 0.14, green: 0.42, blue: 0.62)) {
                Text("\(controller.billingAccountCount)")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("\(controller.activeKeyCount) active keys")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            RelayMetricTile(title: "Available Credits", accent: Color(red: 0.61, green: 0.31, blue: 0.18)) {
                Text("\(controller.totalManagedCredits)")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Across all managed accounts")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Runtime section

    private var runtimeSection: some View {
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

    // MARK: - Helpers

    private var statusBadge: some View {
        RelayPill(icon: statusSymbol, text: controller.statusText, tint: statusColor)
    }

    private var statusColor: Color {
        switch controller.status {
        case .stopped:  return Color.gray
        case .starting: return Color.orange
        case .running:  return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .failed:   return Color.red
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .stopped:  return "pause.circle.fill"
        case .starting: return "arrow.triangle.2.circlepath.circle.fill"
        case .running:  return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        }
    }

    private var successRateText: String {
        guard let successRate = controller.requestSuccessRate else { return "N/A" }
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

    private func formattedDuration(from start: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let hours   = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0   { return String(format: "%02dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%02dm %02ds", minutes, seconds) }
        return String(format: "%02ds", seconds)
    }
}
