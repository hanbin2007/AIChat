//
//  RelayFocusedValues.swift
//  AIChat Relay
//
//  Navigation types, sidebar model, and FocusedValue bridge for the menu bar.
//

import SwiftUI

// MARK: - Sidebar navigation model

enum RelaySidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard     = "Dashboard"
    case connectivity  = "Connectivity"
    case billing       = "Billing"
    case settings      = "Settings"
    case console       = "Console"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:    return "gauge.with.dots.needle.67percent"
        case .connectivity: return "network"
        case .billing:      return "creditcard"
        case .settings:     return "gearshape"
        case .console:      return "terminal"
        }
    }

    var sectionTitle: String {
        switch self {
        case .dashboard, .connectivity: return "OVERVIEW"
        case .billing, .settings:       return "MANAGE"
        case .console:                  return "DIAGNOSTICS"
        }
    }

    static var sections: [(title: String, items: [RelaySidebarItem])] {
        [
            ("OVERVIEW",     [.dashboard, .connectivity]),
            ("MANAGE",       [.billing, .settings]),
            ("DIAGNOSTICS",  [.console]),
        ]
    }
}

// MARK: - Console sub-tab (promoted from private)

enum RelayConsoleTab: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case debug    = "Debug"

    var id: String { rawValue }
}

// MARK: - Menu state bridge

@MainActor
struct RelayMenuState {
    let controller: RelayServerController
    let selectedItem: Binding<RelaySidebarItem>
    let showsSecrets: Binding<Bool>
}

// MARK: - FocusedValueKey

struct RelayMenuStateKey: FocusedValueKey {
    typealias Value = RelayMenuState
}

extension FocusedValues {
    var relayMenuState: RelayMenuState? {
        get { self[RelayMenuStateKey.self] }
        set { self[RelayMenuStateKey.self] = newValue }
    }
}
