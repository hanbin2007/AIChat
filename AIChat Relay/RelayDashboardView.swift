//
//  RelayDashboardView.swift
//  AIChat Relay
//
//  Root view — sidebar navigation + content area.
//  Individual pages are in dedicated files; shared design tokens in RelayDesignTokens.
//

import SwiftUI

struct RelayDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: RelayServerController
    @ObservedObject private var settings: RelaySettingsStore

    @State private var selectedItem: RelaySidebarItem = .dashboard
    @State private var showsSecrets = false

    init(controller: RelayServerController) {
        self.controller = controller
        self._settings = ObservedObject(wrappedValue: controller.settings)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            dashboardBackground

            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            } detail: {
                selectedPageContent
            }

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
        .animation(.snappy(duration: 0.35, extraBounce: 0.06), value: selectedItem)
        .focusedSceneValue(\.relayMenuState, RelayMenuState(
            controller: controller,
            selectedItem: $selectedItem,
            showsSecrets: $showsSecrets
        ))
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .overlay(relayDividerColor(colorScheme))
                .padding(.horizontal, 12)

            List(selection: $selectedItem) {
                ForEach(RelaySidebarItem.sections, id: \.title) { section in
                    Section {
                        ForEach(section.items) { item in
                            sidebarRow(for: item)
                                .tag(item)
                        }
                    } header: {
                        Text(section.title)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .overlay(relayDividerColor(colorScheme))
                .padding(.horizontal, 12)

            sidebarFooter
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("AIChat Relay")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)

                    Text(sidebarStatusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var sidebarFooter: some View {
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
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(primaryActionTint)
    }

    @ViewBuilder
    private func sidebarRow(for item: RelaySidebarItem) -> some View {
        Label {
            Text(item.rawValue)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(selectedItem == item ? .primary : .secondary)
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var selectedPageContent: some View {
        switch selectedItem {
        case .dashboard:
            RelayDashboardPage(controller: controller)
        case .connectivity:
            RelayConnectivityPage(controller: controller)
        case .billing:
            RelayBillingWorkspaceView(controller: controller)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .settings:
            RelaySettingsPage(controller: controller)
        case .console:
            RelayConsoleWorkspaceView(controller: controller)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Background

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

    // MARK: - Helpers

    private var statusDotColor: Color {
        switch controller.status {
        case .stopped:  return Color.gray
        case .starting: return Color.orange
        case .running:  return Color.green
        case .failed:   return Color.red
        }
    }

    private var sidebarStatusText: String {
        switch controller.status {
        case .stopped:        return "Stopped"
        case .starting:       return "Starting\u{2026}"
        case .running:
            if let port = settings.validatedPort {
                return "Running on :\(port)"
            }
            return "Running"
        case .failed:         return "Failed"
        }
    }

    private var primaryActionTitle: String {
        if controller.isStarting { return "Starting\u{2026}" }
        return controller.isRunning ? "Stop Relay" : "Start Relay"
    }

    private var primaryActionTint: Color {
        switch controller.status {
        case .running:  return Color.red
        case .starting: return Color.orange
        case .failed:   return Color.red
        case .stopped:  return Color(red: 0.08, green: 0.38, blue: 0.44)
        }
    }
}
