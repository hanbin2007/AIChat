import Foundation
import Combine

/// Single @MainActor source of truth for entitlement state.
/// Orchestrates RelayClient (network), EntitlementCache (persistence),
/// and EntitlementEngine (pure functional core). No UI logic here.
@MainActor
final class EntitlementStore: ObservableObject {
    @Published private(set) var state: EntitlementState
    private let client: RelayClient
    private let cache: EntitlementCache
    private let now: () -> Date
    @Published var platformConfigured: Bool

    init(
        client: RelayClient,
        cache: EntitlementCache,
        platformConfigured: Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.cache = cache
        self.platformConfigured = platformConfigured
        self.now = now
        self.state = cache.load() ?? EntitlementState()
    }

    // MARK: - Derived decision (live projection, no storage)

    var decision: EntitlementDecision {
        EntitlementEngine.derive(state, now: now(), platformConfigured: platformConfigured)
    }

    // MARK: - Mutations

    func apply(_ event: EntitlementEvent) {
        state = EntitlementEngine.reduce(state, event)
        try? cache.save(state)
    }

    func refresh() async {
        do {
            let snap = try await client.fetchSnapshot()
            apply(.relayRefreshed(snap, now: now()))
        } catch RelayError.unauthorized {
            apply(.relayRefreshFailed(hard: .revoked, now: now()))
        } catch RelayError.notConfigured {
            apply(.signedOut)
        } catch {
            apply(.relayRefreshFailed(hard: nil, now: now()))
        }
    }

    func recordSpend(_ cost: Int) {
        apply(.messageConsumed(cost: cost))
    }

    func estimatedCost(
        model: ModelID,
        inputTokens: Int,
        outputTokens: Int,
        usesSearch: Bool
    ) -> Int {
        guard let snap = state.account else { return 0 }
        return EntitlementEngine.estimatedCost(
            snapshot: snap,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            usesSearch: usesSearch
        )
    }

    func signOut() {
        apply(.signedOut)
    }
}
