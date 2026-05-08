//
//  ActivationCenterViewModel.swift
//  AIChat Watch App
//
//  Drives the activation screen. Handles bootstrap (first-launch trial),
//  offline-code redemption, and surfacing the current account state
//  for display. Pairing-token issuance is a separate VM
//  (`RelayPairingTokenViewModel`) so each screen stays narrow.
//

import Foundation
import Observation

@Observable
@MainActor
final class ActivationCenterViewModel {

    enum ActionState: Equatable {
        case idle
        case running
        case success
        case failed(String)
    }

    private(set) var status: RelayAccountStatusResponse?
    private(set) var bootstrapState: ActionState = .idle
    private(set) var offlineRedeemState: ActionState = .idle

    private let service: RelayActivationService

    init(service: RelayActivationService) {
        self.service = service
    }

    var currentBearerKey: String? { status?.key?.keyValue }
    var creditBalance: Int? { status?.account?.creditBalance }

    func bootstrap() async {
        bootstrapState = .running
        do {
            status = try await service.bootstrap()
            bootstrapState = .success
        } catch {
            bootstrapState = .failed(error.localizedDescription)
        }
    }

    func refreshStatus() async {
        do {
            status = try await service.accountStatus()
        } catch {
            // Keep last good status; surface error to bootstrapState
            // only if we have nothing cached.
            if status == nil {
                bootstrapState = .failed(error.localizedDescription)
            }
        }
    }

    func redeemOffline(
        code: String,
        creditsTotal: Int? = nil,
        creditsRemaining: Int? = nil,
        validUntil: Date? = nil,
        allowedModelIDs: [String]? = nil,
        fingerprint: String? = nil
    ) async {
        offlineRedeemState = .running
        do {
            status = try await service.exchangeOffline(
                code: code,
                creditsTotal: creditsTotal,
                creditsRemaining: creditsRemaining,
                validUntil: validUntil,
                allowedModelIDs: allowedModelIDs,
                fingerprint: fingerprint
            )
            offlineRedeemState = .success
        } catch {
            offlineRedeemState = .failed(error.localizedDescription)
        }
    }
}
