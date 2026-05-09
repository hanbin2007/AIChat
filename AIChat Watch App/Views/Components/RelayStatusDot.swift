//
//  RelayStatusDot.swift
//  AIChat Watch App
//
//  Small (8pt) status dot that mirrors `RelayConnectionMonitor.state`.
//  Placed in toolbars to give an at-a-glance view of relay reachability.
//

import SwiftUI

struct RelayStatusDot: View {
    let state: RelayConnectionMonitor.State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(accessibilityLabel)
    }

    private var color: Color {
        switch state {
        case .online: return DS.Status.ok
        case .connecting: return DS.Status.warn
        case .offline: return DS.Status.danger
        case .unknown: return Color.secondary.opacity(0.5)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .online: return "Relay online"
        case .connecting: return "Relay connecting"
        case .offline(let reason): return "Relay offline: \(reason)"
        case .unknown: return "Relay status unknown"
        }
    }
}
