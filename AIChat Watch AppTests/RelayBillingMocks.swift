//
//  RelayBillingMocks.swift
//  AIChat Watch AppTests
//
//  In-memory test doubles for `BillingNetworking` and
//  `ActivationNetworking`. Each method is backed by a closure that
//  defaults to fatalError so a missing stub is loud — silent passes
//  hide test gaps.
//

import Foundation
@testable import AIChat_Watch_App

final class MockBillingNetworking: BillingNetworking, ActivationNetworking, @unchecked Sendable {
    var onBillingCatalog: () -> Result<RelayCatalogResponse, Error> = {
        .failure(MockError.notStubbed("billingCatalog"))
    }
    var onAccountStatus: () -> Result<RelayAccountStatusResponse, Error> = {
        .failure(MockError.notStubbed("accountStatus"))
    }
    var onPreparePurchase: (RelayPurchasePrepareRequest) -> Result<RelayPurchasePrepareResponse, Error> = { _ in
        .failure(MockError.notStubbed("preparePurchase"))
    }
    var onSubmitPurchase: (RelayPurchaseSubmitRequest) -> Result<RelayPurchaseSubmissionResponse, Error> = { _ in
        .failure(MockError.notStubbed("submitPurchase"))
    }
    var onRestorePurchases: (RelayRestorePurchasesRequest) -> Result<RelayPurchaseSubmissionResponse, Error> = { _ in
        .failure(MockError.notStubbed("restorePurchases"))
    }
    var onBootstrapActivation: (RelayActivationBootstrapRequest) -> Result<RelayAccountStatusResponse, Error> = { _ in
        .failure(MockError.notStubbed("bootstrapActivation"))
    }
    var onIssuePairingToken: () -> Result<RelayPairingTokenResponse, Error> = {
        .failure(MockError.notStubbed("issuePairingToken"))
    }
    var onJoinPaired: (RelayJoinPairedRequest) -> Result<RelayAccountStatusResponse, Error> = { _ in
        .failure(MockError.notStubbed("joinPaired"))
    }
    var onExchangeOffline: (RelayOfflineExchangeRequest) -> Result<RelayAccountStatusResponse, Error> = { _ in
        .failure(MockError.notStubbed("exchangeOffline"))
    }

    func billingCatalog() async throws -> RelayCatalogResponse {
        try onBillingCatalog().get()
    }
    func accountStatus() async throws -> RelayAccountStatusResponse {
        try onAccountStatus().get()
    }
    func preparePurchase(_ payload: RelayPurchasePrepareRequest) async throws -> RelayPurchasePrepareResponse {
        try onPreparePurchase(payload).get()
    }
    func submitPurchase(_ payload: RelayPurchaseSubmitRequest) async throws -> RelayPurchaseSubmissionResponse {
        try onSubmitPurchase(payload).get()
    }
    func restorePurchases(_ payload: RelayRestorePurchasesRequest) async throws -> RelayPurchaseSubmissionResponse {
        try onRestorePurchases(payload).get()
    }
    func bootstrapActivation(_ payload: RelayActivationBootstrapRequest) async throws -> RelayAccountStatusResponse {
        try onBootstrapActivation(payload).get()
    }
    func issuePairingToken() async throws -> RelayPairingTokenResponse {
        try onIssuePairingToken().get()
    }
    func joinPaired(_ payload: RelayJoinPairedRequest) async throws -> RelayAccountStatusResponse {
        try onJoinPaired(payload).get()
    }
    func exchangeOffline(_ payload: RelayOfflineExchangeRequest) async throws -> RelayAccountStatusResponse {
        try onExchangeOffline(payload).get()
    }
}

enum MockError: LocalizedError, Equatable {
    case notStubbed(String)
    case forced(String)

    var errorDescription: String? {
        switch self {
        case .notStubbed(let method):
            return "Mock method \(method) was called without a stubbed result."
        case .forced(let message):
            return message
        }
    }
}

enum RelayBillingFixtures {
    static func deviceIdentity(id: String = "device-1") -> WatchDeviceIdentity {
        WatchDeviceIdentity(rawIdentifier: id, deviceToken: 0, displayToken: "0000")
    }

    static func catalog(
        plans: [RelayPlanCatalogItem] = [],
        lowBalanceThreshold: Int = 300
    ) -> RelayCatalogResponse {
        RelayCatalogResponse(
            plans: plans,
            meteringPolicy: RelayMeteringPolicySnapshot(
                creditBudgetUSDPer1000Credits: Decimal(5),
                trialCredits: 800,
                trialDurationDays: 7,
                lowBalanceThresholdCredits: lowBalanceThreshold,
                maxBoundDevices: 5,
                creditMultiplier: Decimal(1),
                rates: []
            )
        )
    }

    static func accountStatus(
        creditBalance: Int = 1000,
        keyValue: String = "rk_test"
    ) -> RelayAccountStatusResponse {
        RelayAccountStatusResponse(
            account: RelayAccountSummary(
                accountID: UUID(),
                displayName: nil,
                adminNote: nil,
                state: .active,
                source: .trial,
                planID: nil,
                originalTransactionID: nil,
                appAccountToken: nil,
                creditBalance: creditBalance,
                creditExpiresAt: nil,
                lastUsageAt: nil
            ),
            device: nil,
            key: RelayKeySummary(
                keyID: UUID(),
                keyValue: keyValue,
                state: .active,
                source: .trial,
                note: nil,
                issuedAt: Date()
            ),
            grants: [],
            recentUsage: []
        )
    }
}
