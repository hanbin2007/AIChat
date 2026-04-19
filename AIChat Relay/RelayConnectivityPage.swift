//
//  RelayConnectivityPage.swift
//  AIChat Relay
//
//  Client connectivity page — endpoints, base URL, and xcconfig snippet.
//

import SwiftUI

struct RelayConnectivityPage: View {
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
                endpointsSection
                snippetSection
                bindingInfoSection
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Endpoints

    private var endpointsSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client Setup")
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        Text("Copy a stable base URL and generated xcconfig values without leaving the dashboard.")
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
            }
        }
    }

    // MARK: - Snippet

    private var snippetSection: some View {
        RelayPanel {
            VStack(alignment: .leading, spacing: 14) {
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

    // MARK: - Binding info

    private var bindingInfoSection: some View {
        RelayPanel {
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
