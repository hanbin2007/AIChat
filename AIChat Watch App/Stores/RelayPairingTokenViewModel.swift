//
//  RelayPairingTokenViewModel.swift
//  AIChat Watch App
//
//  Drives the "pair another device" screen. Issues a fresh token from
//  `/v1/account/pairing-token` and surfaces the remaining lifetime so
//  the view can display a countdown next to the QR/text.
//

import Foundation
import Observation

@Observable
@MainActor
final class RelayPairingTokenViewModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var token: String?
    private(set) var expiresAt: Date?
    private(set) var loadState: LoadState = .idle

    private let service: RelayActivationService
    private let now: @Sendable () -> Date

    init(service: RelayActivationService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    /// Seconds remaining until the current token expires. `nil` when no
    /// token is loaded; clamped to zero once expired.
    var remainingTime: TimeInterval? {
        guard let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(now()))
    }

    var isExpired: Bool {
        guard let remaining = remainingTime else { return false }
        return remaining <= 0
    }

    func issueNewToken() async {
        loadState = .loading
        do {
            let response = try await service.requestPairingToken()
            token = response.pairingToken
            expiresAt = response.expiresAt
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
