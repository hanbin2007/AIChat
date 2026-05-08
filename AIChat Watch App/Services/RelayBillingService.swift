//
//  RelayBillingService.swift
//  AIChat Watch App
//
//  MVVM service layer over `Networking/RelayAPIClient`. Owns the
//  billing-related calls a ViewModel needs (catalog, account status,
//  purchase prepare/submit/restore). Injection is via the
//  `BillingNetworking` protocol so ViewModels can be unit-tested with
//  in-memory mocks.
//
//  StoreKit 2 wiring (the actual on-device purchase) is **not** part of
//  this service — it lives in a future `BillingPurchaseCoordinator`
//  that orchestrates `Product.purchase()` ↔ relay. This service stays
//  pure-network so it stays small and testable.
//

import Foundation

/// Narrow protocol the watch needs from the relay billing surface.
/// `RelayAPIClient` conforms; tests inject a mock.
protocol BillingNetworking: Sendable {
    func billingCatalog() async throws -> RelayCatalogResponse
    func accountStatus() async throws -> RelayAccountStatusResponse
    func preparePurchase(_ payload: RelayPurchasePrepareRequest) async throws -> RelayPurchasePrepareResponse
    func submitPurchase(_ payload: RelayPurchaseSubmitRequest) async throws -> RelayPurchaseSubmissionResponse
    func restorePurchases(_ payload: RelayRestorePurchasesRequest) async throws -> RelayPurchaseSubmissionResponse
}

extension RelayAPIClient: BillingNetworking {}

/// Aggregated state ViewModels render from. `lowBalance` is computed
/// against the catalog's `meteringPolicy.lowBalanceThresholdCredits`
/// when both are present.
struct BillingSnapshot: Equatable, Sendable {
    var catalog: RelayCatalogResponse?
    var accountStatus: RelayAccountStatusResponse?
    var lastRefreshedAt: Date?

    var creditBalance: Int? { accountStatus?.account?.creditBalance }

    var lowBalance: Bool {
        guard let balance = creditBalance,
              let threshold = catalog?.meteringPolicy.lowBalanceThresholdCredits
        else { return false }
        return balance <= threshold
    }
}

/// Stateless service — every call goes to the network. Subscribers
/// drive their own caching in the ViewModel layer or in
/// `BillingPersistence` (Phase 2).
actor RelayBillingService {
    private let networking: BillingNetworking
    private let deviceIdentity: WatchDeviceIdentity
    private let platform: RelayDevicePlatform

    init(
        networking: BillingNetworking,
        deviceIdentity: WatchDeviceIdentity,
        platform: RelayDevicePlatform = RelayBillingService.currentPlatform
    ) {
        self.networking = networking
        self.deviceIdentity = deviceIdentity
        self.platform = platform
    }

    func loadSnapshot() async throws -> BillingSnapshot {
        let catalog = try await networking.billingCatalog()
        let status: RelayAccountStatusResponse?
        do {
            status = try await networking.accountStatus()
        } catch {
            // Account status is best-effort — a freshly-bootstrapped
            // device may not have one yet, and we don't want to fail
            // the whole snapshot on it. The catalog failure above is
            // the one that propagates because the UI can't render
            // without plans + thresholds.
            status = nil
        }
        return BillingSnapshot(
            catalog: catalog,
            accountStatus: status,
            lastRefreshedAt: Date()
        )
    }

    func loadCatalog() async throws -> RelayCatalogResponse {
        try await networking.billingCatalog()
    }

    func loadAccountStatus() async throws -> RelayAccountStatusResponse {
        try await networking.accountStatus()
    }

    /// Phase 1 of an in-app purchase: fetches the relay-issued
    /// `appAccountToken` to attach to `Product.purchase(options:)` so
    /// the StoreKit transaction can be matched to this account.
    func preparePurchase() async throws -> RelayPurchasePrepareResponse {
        let payload = RelayPurchasePrepareRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform
        )
        return try await networking.preparePurchase(payload)
    }

    /// Phase 2 of an in-app purchase: hands the JWS-signed transaction
    /// to the relay for credit grant.
    func submitPurchase(transaction: RelaySubmittedTransaction) async throws -> RelayAccountStatusResponse {
        let payload = RelayPurchaseSubmitRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform,
            transaction: transaction
        )
        let response = try await networking.submitPurchase(payload)
        return response.status
    }

    func restorePurchases(transactions: [RelaySubmittedTransaction]) async throws -> RelayAccountStatusResponse {
        let payload = RelayRestorePurchasesRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: platform,
            transactions: transactions
        )
        let response = try await networking.restorePurchases(payload)
        return response.status
    }

    nonisolated static var currentPlatform: RelayDevicePlatform {
        #if os(watchOS)
        return .watch
        #elseif os(iOS)
        return .iPhone
        #elseif os(macOS)
        return .mac
        #else
        return .unknown
        #endif
    }
}
