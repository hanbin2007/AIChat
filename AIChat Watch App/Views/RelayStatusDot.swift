//
//  RelayStatusDot.swift
//  AIChat Watch App
//
//  Toolbar indicator that surfaces `ChatStore.relayConnectionStatus`
//  with a 7pt colored dot inside a 44pt hitbox. Relay mode only — the
//  caller gates visibility on `configuration.backendMode == .relay`.
//

#if os(watchOS)
import SwiftUI

struct RelayStatusDot: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingDetail = false

    private static let dotDiameter: CGFloat = 7
    private static let hitboxSide: CGFloat = 44

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            ZStack {
                Color.clear
                    .frame(width: Self.hitboxSide, height: Self.hitboxSide)
                Circle()
                    .fill(color(for: chatStore.relayConnectionStatus))
                    .frame(width: Self.dotDiameter, height: Self.dotDiameter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel(for: chatStore.relayConnectionStatus)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("relay-status-dot")
        .sheet(isPresented: $isShowingDetail) {
            RelayStatusDetailSheet(isPresented: $isShowingDetail)
                .environmentObject(chatStore)
        }
    }

    private func color(for status: RelayConnectionStatus) -> Color {
        switch status {
        case .online:
            return .green
        case .connecting, .unknown:
            return .yellow
        case .offline:
            return .red
        }
    }

    private func accessibilityLabel(for status: RelayConnectionStatus) -> String {
        switch status {
        case .unknown:
            return "Relay status unknown"
        case .connecting:
            return "Relay connecting"
        case .online:
            return "Relay online"
        case .offline(let reason):
            return "Relay offline: \(reason)"
        }
    }
}

private struct RelayStatusDetailSheet: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                statusHeader
                Divider()
                serverRow
                if let lastSuccess = chatStore.relayLastSuccessAt {
                    timestampRow(label: "Last success", value: lastSuccess)
                }
                if let lastFailure = chatStore.relayLastFailureAt {
                    timestampRow(label: "Last failure", value: lastFailure)
                }
                if case .offline(let reason) = chatStore.relayConnectionStatus {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task {
                        await chatStore.retryLatestRelayFailure()
                        isPresented = false
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("relay-status-retry")
                .padding(.top, 6)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .navigationTitle("Relay Status")
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(headerColor)
                .frame(width: 10, height: 10)
            Text(headerTitle)
                .font(.headline)
            Spacer(minLength: 0)
        }
    }

    private var headerTitle: String {
        switch chatStore.relayConnectionStatus {
        case .unknown:
            return "Unknown"
        case .connecting:
            return "Connecting"
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        }
    }

    private var headerColor: Color {
        switch chatStore.relayConnectionStatus {
        case .online:
            return .green
        case .connecting, .unknown:
            return .yellow
        case .offline:
            return .red
        }
    }

    private var serverRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Server")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(serverHostText)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var serverHostText: String {
        // Show only the configured base URL (scheme + host + port) —
        // never the bearer token. The bearer lives in a separate
        // credential slot and is explicitly excluded from this sheet.
        guard let url = chatStore.configuration.relayBaseURL else {
            return "—"
        }

        if let scheme = url.scheme, let host = url.host() {
            if let port = url.port {
                return "\(scheme)://\(host):\(port)"
            }
            return "\(scheme)://\(host)"
        }

        return url.absoluteString
    }

    private func timestampRow(label: String, value: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .dateTime.hour().minute().second())
                .font(.footnote)
        }
    }
}
#endif
