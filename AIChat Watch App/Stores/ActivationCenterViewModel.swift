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
    private let appGroupIdentifier: String?

    init(service: RelayActivationService, appGroupIdentifier: String?) {
        self.service = service
        self.appGroupIdentifier = appGroupIdentifier
    }

    var currentBearerKey: String? { status?.key?.keyValue }
    var creditBalance: Int? { status?.account?.creditBalance }

    func bootstrap() async {
        bootstrapState = .running
        do {
            let response = try await service.bootstrap()
            status = response
            persistBearerKey(from: response)
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
            let response = try await service.exchangeOffline(
                code: code,
                creditsTotal: creditsTotal,
                creditsRemaining: creditsRemaining,
                validUntil: validUntil,
                allowedModelIDs: allowedModelIDs,
                fingerprint: fingerprint
            )
            status = response
            persistBearerKey(from: response)
            offlineRedeemState = .success
        } catch {
            offlineRedeemState = .failed(error.localizedDescription)
        }
    }

    // The relay's bootstrap / offline-exchange responses carry the
    // device-scoped `rk_*` key the watch must persist; without this
    // write a fresh install loses its key on the next launch and
    // every subsequent relay call is unauthenticated.
    private func persistBearerKey(from response: RelayAccountStatusResponse) {
        RelayKeyStore.set(response.key?.keyValue, appGroupIdentifier: appGroupIdentifier)
    }
}
