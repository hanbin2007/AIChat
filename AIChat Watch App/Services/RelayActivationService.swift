//
//  RelayActivationService.swift
//  AIChat Watch App
//
//  MVVM service layer over `Networking/RelayAPIClient` for activation,
//  pairing, and offline-code redemption. Persistence (caching the
//  issued `rk_*` key + account status) is **not** done here — that
//  happens in `BillingPersistence` (Phase 2). This service is purely
//  the relay-call layer, injected into ViewModels via
//  `ActivationNetworking`.
//

import Foundation

protocol ActivationNetworking: Sendable {
    func bootstrapActivation(_ payload: RelayActivationBootstrapRequest) async throws -> RelayAccountStatusResponse
    func issuePairingToken() async throws -> RelayPairingTokenResponse
    func joinPaired(_ payload: RelayJoinPairedRequest) async throws -> RelayAccountStatusResponse
    func exchangeOffline(_ payload: RelayOfflineExchangeRequest) async throws -> RelayAccountStatusResponse
    func accountStatus() async throws -> RelayAccountStatusResponse
}

extension RelayAPIClient: ActivationNetworking {}

actor RelayActivationService {
    private let networking: ActivationNetworking
    private let deviceIdentity: WatchDeviceIdentity
    private let platform: RelayDevicePlatform
    private let deviceAlias: String

    init(
        networking: ActivationNetworking,
        deviceIdentity: WatchDeviceIdentity,
        platform: RelayDevicePlatform = RelayBillingService.currentPlatform,
        deviceAlias: String = Self.defaultDeviceAlias()
    ) {
        self.networking = networking
        self.deviceIdentity = deviceIdentity
        self.platform = platform
        self.deviceAlias = deviceAlias
    }

    /// Bootstraps a new trial account (or no-ops to existing one) and
    /// returns the relay's account status, including the device key
    /// (`rk_*`) the watch should use for subsequent calls.
    func bootstrap() async throws -> RelayAccountStatusResponse {
        let payload = RelayActivationBootstrapRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform,
            deviceAlias: deviceAlias
        )
        return try await networking.bootstrapActivation(payload)
    }

    /// Requests a 10-minute pairing token so another device can call
    /// `/v1/account/join-paired` and bind itself to this account.
    /// Authenticated with the current device's key.
    func requestPairingToken() async throws -> RelayPairingTokenResponse {
        try await networking.issuePairingToken()
    }

    /// Redeems a pairing token issued by another device on the same
    /// account. Replaces this device's key/account state with the
    /// shared one.
    func joinPaired(token: String) async throws -> RelayAccountStatusResponse {
        let payload = RelayJoinPairedRequest(
            pairingToken: token,
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform,
            deviceAlias: deviceAlias
        )
        return try await networking.joinPaired(payload)
    }

    /// Redeems an offline activation code. Sends the credit budget the
    /// caller computed locally so the relay can mirror the offline grant.
    func exchangeOffline(
        code: String,
        creditsTotal: Int?,
        creditsRemaining: Int?,
        validUntil: Date?,
        allowedModelIDs: [String]?,
        fingerprint: String?
    ) async throws -> RelayAccountStatusResponse {
        let payload = RelayOfflineExchangeRequest(
            activationCode: code,
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform,
            deviceAlias: deviceAlias,
            creditsTotal: creditsTotal,
            creditsRemaining: creditsRemaining,
            validUntil: validUntil,
            allowedModelIDs: allowedModelIDs,
            activationFingerprint: fingerprint
        )
        return try await networking.exchangeOffline(payload)
    }

    func accountStatus() async throws -> RelayAccountStatusResponse {
        try await networking.accountStatus()
    }

    nonisolated static func defaultDeviceAlias() -> String {
        #if os(watchOS)
        return "Apple Watch"
        #elseif os(iOS)
        return "iPhone"
        #elseif os(macOS)
        return "Mac"
        #else
        return "Device"
        #endif
    }
}
