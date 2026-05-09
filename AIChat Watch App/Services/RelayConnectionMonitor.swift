//
//  RelayConnectionMonitor.swift
//  AIChat Watch App
//
//  @MainActor observable that tracks the watch's current view of relay
//  reachability — the `connecting` / `online` / `offline(reason:)`
//  state that ChatStreamSession reports through callbacks.
//
//  Replaces the legacy `RelayConnectionStatusHandler`-based pump that
//  ChatStore subscribed to. ViewModels read `state` directly; the
//  publisher is the `Observable` framework, no Combine.
//

import Foundation
import Observation

@Observable
@MainActor
final class RelayConnectionMonitor {
    enum State: Equatable, Sendable {
        case unknown
        case connecting
        case online
        case offline(reason: String)
    }

    private(set) var state: State = .unknown

    func reportConnecting() {
        state = .connecting
    }

    func reportOnline() {
        state = .online
    }

    func reportOffline(reason: String) {
        state = .offline(reason: reason)
    }

    /// Convenience pretty-printer for diagnostics chrome.
    var description: String {
        switch state {
        case .unknown: return "—"
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .offline(let reason): return reason
        }
    }
}
