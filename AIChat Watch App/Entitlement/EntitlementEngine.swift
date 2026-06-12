import Foundation

/// Pure functional core of the activation system. Zero IO, zero side effects.
/// `reduce` evolves persisted state; `derive` produces the single decision every
/// consumer reads (spec §4/§5/§6). Time is injected via parameters (replayable).
nonisolated enum EntitlementEngine {
    static let defaultGraceWindow: TimeInterval = 7 * 24 * 3600  // spec §13: 7 days

    // MARK: - Derive (single decision outlet)

    static func derive(
        _ state: EntitlementState,
        now: Date,
        platformConfigured: Bool,
        graceWindow: TimeInterval = defaultGraceWindow
    ) -> EntitlementDecision {
        func lock(_ r: LockReason, _ cta: ActionableCTA?) -> EntitlementDecision {
            EntitlementDecision(capability: .readOnly(r), availableModels: [], credits: nil, cta: cta)
        }

        // Branch 0: known hard failure (401/revoke/pause) — always overrides grace.
        if let e = state.lastError, e == .revoked || e == .paused {
            return lock(.revoked, .reenterCode)
        }
        // Branch 1: platform not configured (orthogonal to authorization, spec §4 rule 2).
        if !platformConfigured {
            return lock(.platformNotConfigured, .configurePlatform)
        }
        // Branch 2/3: no account.
        guard let snap = state.account else {
            return state.pending != nil
                ? EntitlementDecision(capability: .bootstrapping, availableModels: [], credits: nil, cta: nil)
                : lock(.noAccount, .activate)
        }

        // Revoked/paused reported by a successful refresh (vs the 401 path in branch 0).
        if snap.keyState == .revoked || snap.accountState == .paused {
            return lock(.revoked, .reenterCode)
        }
        // Expired: server account state, or credit expiry timestamp passed.
        if snap.accountState == .expired {
            return lock(.expired, .renew)
        }
        if let exp = snap.creditExpiresAt, exp <= now {
            return lock(.expired, .renew)
        }
        // Exhausted: effective balance (authoritative server balance minus optimistic local spend).
        let effective = snap.creditBalance - state.localSpend
        if effective <= 0 {
            return lock(.exhausted, .renew)
        }
        // Offline grace elapsed: no successful verification within the window.
        if let lv = state.lastVerifiedAt, now.timeIntervalSince(lv) > graceWindow {
            return lock(.offlineGraceElapsed, .goOnline)
        }
        // Ready.
        return EntitlementDecision(
            capability: .ready,
            availableModels: snap.availableModels,
            credits: CreditView(balance: effective, expiresAt: snap.creditExpiresAt),
            cta: nil
        )
    }

    // MARK: - Reduce (state transitions)

    static func reduce(_ state: EntitlementState, _ event: EntitlementEvent) -> EntitlementState {
        var s = state
        switch event {
        case let .relayRefreshed(snap, now), let .purchaseApplied(snap, now), let .exchangeSucceeded(snap, now):
            s.account = snap
            s.lastVerifiedAt = now
            s.localSpend = 0      // server balance is authoritative (spec §6 reconcile)
            s.lastError = nil
            s.pending = nil       // precedence: having access drops a pending exchange
        case let .relayRefreshFailed(hard, _):
            if let hard { s.lastError = hard }   // soft failures leave state intact
        case let .offlineCodeEntered(code):
            if s.account == nil { s.pending = .offlineCode(code) }
        case let .pairedTokenReceived(token):
            if s.account == nil { s.pending = .pairedToken(token) }
        case let .messageConsumed(cost):
            s.localSpend += max(0, cost)
        case .keyRevoked:
            s.lastError = .revoked
        case .signedOut:
            s = EntitlementState()  // full reset
        }
        return s
    }

    // MARK: - Projection (wire types -> clean snapshot)

    /// Pure projection from wire types into the engine's clean snapshot.
    static func project(
        account: RelayAccountSummary,
        key: RelayKeySummary,
        rates: [RelayMeteringRate]
    ) -> RelaySnapshot {
        var rateMap: [ModelID: ModelRate] = [:]
        for r in rates {
            rateMap[r.modelID] = ModelRate(
                inputCreditsPerMillion: r.inputCreditsPerMillion,
                outputCreditsPerMillion: r.outputCreditsPerMillion,
                searchSurchargeCredits: r.searchSurchargeCredits
            )
        }
        return RelaySnapshot(
            accountID: account.accountID,
            accountState: account.state,
            source: account.source,
            keyValue: key.keyValue,
            keyState: key.state,
            creditBalance: account.creditBalance,
            creditExpiresAt: account.creditExpiresAt,
            availableModels: rates.map(\.modelID),
            rates: rateMap
        )
    }

    // MARK: - Cost estimation (local optimistic spend)

    /// Local optimistic cost estimate (credits). Server remains authoritative; this drives UX only.
    static func estimatedCost(
        snapshot: RelaySnapshot,
        model: ModelID,
        inputTokens: Int,
        outputTokens: Int,
        usesSearch: Bool
    ) -> Int {
        guard let rate = snapshot.rates[model] else { return 0 }
        let inCost = Int((Double(inputTokens) / 1_000_000.0 * Double(rate.inputCreditsPerMillion)).rounded())
        let outCost = Int((Double(outputTokens) / 1_000_000.0 * Double(rate.outputCreditsPerMillion)).rounded())
        let searchCost = usesSearch ? rate.searchSurchargeCredits : 0
        return inCost + outCost + searchCost
    }
}
