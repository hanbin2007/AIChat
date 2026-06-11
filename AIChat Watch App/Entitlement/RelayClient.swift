import Foundation

enum RelayError: Error, Equatable {
    case unauthorized
    case decodingFailed(String)
    case transport(String)
    case server(Int)
    case notConfigured
}

protocol RelayClient: Sendable {
    func fetchSnapshot() async throws -> RelaySnapshot
}

struct FakeRelayClient: RelayClient {
    var result: Result<RelaySnapshot, RelayError>
    func fetchSnapshot() async throws -> RelaySnapshot {
        switch result {
        case let .success(s): return s
        case let .failure(e): throw e
        }
    }
}

// MARK: - Read seam

/// Narrow protocol that isolates the two HTTP fetches `LiveRelayClient` needs.
/// `RelayAccountService` will conform in a later plan; tests use `StubFetcher`.
protocol RelayStatusFetching: Sendable {
    func fetchAccountStatusForEntitlement() async throws -> RelayAccountStatusResponse?
    func fetchCatalogForEntitlement() async throws -> RelayCatalogResponse
}

// MARK: - Live implementation

struct LiveRelayClient: RelayClient {
    let fetcher: any RelayStatusFetching

    func fetchSnapshot() async throws -> RelaySnapshot {
        let status: RelayAccountStatusResponse?
        do {
            status = try await fetcher.fetchAccountStatusForEntitlement()
        } catch let e as RelayAccountServiceError {
            if case .unauthorized = e { throw RelayError.unauthorized }
            throw RelayError.transport(String(describing: e))
        } catch {
            throw RelayError.transport(String(describing: error))
        }

        guard let status, let account = status.account, let key = status.key else {
            throw RelayError.notConfigured
        }

        let catalog: RelayCatalogResponse
        do {
            catalog = try await fetcher.fetchCatalogForEntitlement()
        } catch {
            throw RelayError.transport(String(describing: error))
        }

        let rates: [RelayMeteringRate] = catalog.meteringPolicy.rates
        return EntitlementEngine.project(account: account, key: key, rates: rates)
    }
}
