//
//  RelayPairingTokenSheet.swift
//  AIChat Watch App
//
//  Modal that issues a 10-minute pairing token so a second device can
//  join this account. Shows the token in a monospaced font with a
//  countdown progress ring. Tapping "Issue New" rolls a fresh token.
//

import SwiftUI

struct RelayPairingTokenSheet: View {
    @Environment(\.appEnvironment) private var environment

    let onDismiss: () -> Void

    @State private var viewModel: RelayPairingTokenViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    // TimelineView ticks every second so the countdown
                    // and remainingTime stay live without a leaked Timer.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        content(vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Pair Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .task {
            guard let env = environment, let service = env.activationService else { return }
            if viewModel == nil {
                let vm = RelayPairingTokenViewModel(service: service)
                viewModel = vm
                await vm.issueNewToken()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: RelayPairingTokenViewModel) -> some View {
        VStack(spacing: DS.Spacing.m) {
            switch vm.loadState {
            case .idle, .loading:
                ProgressView("Generating…")
            case .ready:
                if let token = vm.token {
                    tokenDisplay(token: token, vm: vm)
                } else {
                    Text("No token yet.")
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DS.Status.danger)
            }
            Spacer(minLength: 0)
            Button("Issue New Token") {
                Task { await vm.issueNewToken() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(DS.Spacing.m)
    }

    private func tokenDisplay(token: String, vm: RelayPairingTokenViewModel) -> some View {
        VStack(spacing: DS.Spacing.s) {
            Text(token)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
            if let remaining = vm.remainingTime {
                ProgressView(value: max(0, min(1, remaining / 600)))
                    .tint(remaining < 60 ? DS.Status.danger : DS.Status.info)
                Text(formatRemaining(remaining))
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Expired" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d remaining", mins, secs)
    }
}
