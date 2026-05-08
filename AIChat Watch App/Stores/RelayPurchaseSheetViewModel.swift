//
//  RelayPurchaseSheetViewModel.swift
//  AIChat Watch App
//
//  Drives the credit purchase sheet — list plans, present the
//  watch-side StoreKit affordance, and surface the iPhone fallback if
//  watch StoreKit can't fulfil the purchase.
//
//  StoreKit 2 wiring (the actual `Product.purchase()` call + JWS
//  submit) is deliberately out of scope here; this VM only handles
//  the relay-side prepare/submit/restore round-trips. The full
//  watch-StoreKit ↔ iPhone-fallback orchestration ships in a
//  follow-up `BillingPurchaseCoordinator`.
//

import Foundation
import Observation

@Observable
@MainActor
final class RelayPurchaseSheetViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        case preparing
        case readyToPurchase(appAccountToken: UUID)
        case submitting
        case completed
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var plans: [RelayPlanCatalogItem] = []
    private(set) var balance: Int?

    private let billing: RelayBillingService

    init(billing: RelayBillingService) {
        self.billing = billing
    }

    func loadCatalog() async {
        loadState = .loading
        do {
            let snapshot = try await billing.loadSnapshot()
            plans = snapshot.catalog?.plans ?? []
            balance = snapshot.creditBalance
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Phase 1: ask the relay for the appAccountToken to attach to
    /// `Product.purchase(options:)`. The actual StoreKit call lives
    /// in the future `BillingPurchaseCoordinator`; this VM exposes
    /// the token to the UI so a placeholder button can pretend to
    /// trigger it during development.
    func preparePurchase() async {
        purchaseState = .preparing
        do {
            let response = try await billing.preparePurchase()
            purchaseState = .readyToPurchase(appAccountToken: response.appAccountToken)
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Phase 2: hand a JWS transaction to the relay. The caller is
    /// responsible for producing it (StoreKit 2). On success the new
    /// balance is reflected via `loadCatalog()`.
    func submitPurchase(transaction: RelaySubmittedTransaction) async {
        purchaseState = .submitting
        do {
            let status = try await billing.submitPurchase(transaction: transaction)
            balance = status.account?.creditBalance
            purchaseState = .completed
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restorePurchases(transactions: [RelaySubmittedTransaction]) async {
        purchaseState = .submitting
        do {
            let status = try await billing.restorePurchases(transactions: transactions)
            balance = status.account?.creditBalance
            purchaseState = .completed
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}
