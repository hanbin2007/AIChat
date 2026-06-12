import Foundation

// MARK: - Production fetcher adapter

/// Nonisolated adapter that bridges `RelayAccountService` (a plain struct) into
/// the `Sendable` `RelayStatusFetching` seam.
struct RelayAccountServiceFetcher: RelayStatusFetching {
    let service: RelayAccountService

    func fetchAccountStatusForEntitlement() async throws -> RelayAccountStatusResponse? {
        try await service.fetchAccountStatusIfPossible()
    }

    func fetchCatalogForEntitlement() async throws -> RelayCatalogResponse {
        try await service.fetchCatalog()
    }
}

// MARK: - Factory

@MainActor
enum EntitlementStoreFactory {
    /// Creates a fully-wired production `EntitlementStore`.
    ///
    /// - Parameters:
    ///   - service: The shared `RelayAccountService` instance.
    ///   - configuration: The loaded `AppConfiguration`; used for
    ///     `isAIConfigured` and (via `appGroupIdentifier`) the storage root.
    static func live(
        service: RelayAccountService,
        configuration: AppConfiguration
    ) -> EntitlementStore {
        let client = LiveRelayClient(fetcher: RelayAccountServiceFetcher(service: service))

        let root: URL
        if let result = try? BillingActivationStoreSupport.makeContainer(
            appGroupIdentifier: configuration.appGroupIdentifier,
            overrideRootURL: nil,
            fileManager: .default
        ) {
            root = result.rootURL
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        }

        let cache = EntitlementCache(directory: root)
        return EntitlementStore(
            client: client,
            cache: cache,
            platformConfigured: configuration.isAIConfigured
        )
    }
}
