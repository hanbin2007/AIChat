//
//  BillingViewModel.swift
//  AIChat Watch App
//
//  Strict MVVM ViewModel for the relay billing surface (catalog +
//  balance + low-balance flag). Holds only the state one screen needs.
//  No persistence, no shared store — each screen owns its own VM
//  instance constructed via `AppEnvironment`.
//

import Foundation
import Observation

@Observable
@MainActor
final class BillingViewModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var snapshot: BillingSnapshot?
    private(set) var loadState: LoadState = .idle

    private let service: RelayBillingService

    init(service: RelayBillingService) {
        self.service = service
    }

    var balance: Int? { snapshot?.creditBalance }
    var lowBalance: Bool { snapshot?.lowBalance ?? false }
    var plans: [RelayPlanCatalogItem] { snapshot?.catalog?.plans ?? [] }

    func refresh() async {
        loadState = .loading
        do {
            let next = try await service.loadSnapshot()
            snapshot = next
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func refreshAccountOnly() async {
        do {
            let status = try await service.loadAccountStatus()
            var existing = snapshot ?? BillingSnapshot()
            existing.accountStatus = status
            existing.lastRefreshedAt = Date()
            snapshot = existing
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
