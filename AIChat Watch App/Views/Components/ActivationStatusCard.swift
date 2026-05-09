//
//  ActivationStatusCard.swift
//  AIChat Watch App
//
//  Card surface for the AccountCenterView header. Renders bearer-key
//  prefix, credit balance, and (when low) a low-balance warning row.
//  Compact enough to fit at the top of a watch screen above the
//  scrollable plan list.
//

import SwiftUI

struct ActivationStatusCard: View {
    let status: RelayAccountStatusResponse?
    let lowBalanceThreshold: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Text("Account")
                    .font(DS.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                Spacer()
                if let state = status?.account?.state {
                    Text(state.rawValue.capitalized)
                        .font(DS.Typography.chip)
                        .padding(.horizontal, DS.Spacing.s)
                        .padding(.vertical, 2)
                        .background(stateBackground(for: state), in: Capsule())
                        .foregroundStyle(stateForeground(for: state))
                }
            }
            balanceRow
            if let key = status?.key?.keyValue {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(prefix(key))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if showsLowBalance {
                Label("Low balance — top up soon", systemImage: "exclamationmark.circle")
                    .font(DS.Typography.bubbleMeta)
                    .foregroundStyle(DS.Status.warn)
            }
        }
        .dsCard()
    }

    private var balanceRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(balanceText)
                .font(.title3.monospacedDigit())
            Text("credits")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var balanceText: String {
        guard let balance = status?.account?.creditBalance else { return "—" }
        return "\(balance)"
    }

    private var showsLowBalance: Bool {
        guard let balance = status?.account?.creditBalance,
              let threshold = lowBalanceThreshold else { return false }
        return balance <= threshold
    }

    private func prefix(_ key: String) -> String {
        guard key.count > 12 else { return key }
        return String(key.prefix(12)) + "…"
    }

    private func stateBackground(for state: RelayAccountState) -> Color {
        switch state {
        case .active: return DS.Status.ok.opacity(0.2)
        case .paused: return DS.Status.warn.opacity(0.2)
        case .expired, .inactive: return DS.Status.danger.opacity(0.2)
        }
    }

    private func stateForeground(for state: RelayAccountState) -> Color {
        switch state {
        case .active: return DS.Status.ok
        case .paused: return DS.Status.warn
        case .expired, .inactive: return DS.Status.danger
        }
    }
}
