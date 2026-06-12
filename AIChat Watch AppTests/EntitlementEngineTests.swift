import XCTest
@testable import AIChat_Watch_App

final class EntitlementEngineTests: XCTestCase {
    // Helper reused across tests.
    func makeSnapshot(
        accountState: RelayAccountState = .active,
        keyState: RelayKeyState = .active,
        creditBalance: Int = 1000,
        creditExpiresAt: Date? = nil,
        models: [ModelID] = ["gemini-3-flash-preview"]
    ) -> RelaySnapshot {
        RelaySnapshot(
            accountID: UUID(),
            accountState: accountState,
            source: .subscription,
            keyValue: "rk_test",
            keyState: keyState,
            creditBalance: creditBalance,
            creditExpiresAt: creditExpiresAt,
            availableModels: models,
            rates: [
                "gemini-3-flash-preview": ModelRate(
                    inputCreditsPerMillion: 100,
                    outputCreditsPerMillion: 300,
                    searchSurchargeCredits: 14
                )
            ]
        )
    }

    // MARK: - Task 1: value types

    func testDecisionEquatableAndConstructs() async throws {
        let a = EntitlementDecision(capability: .ready, availableModels: ["m"], credits: nil, cta: nil)
        let b = EntitlementDecision(capability: .ready, availableModels: ["m"], credits: nil, cta: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.capability, .ready)
    }

    func testEntitlementStateDefaults() async throws {
        let s = EntitlementState()
        XCTAssertNil(s.account)
        XCTAssertEqual(s.localSpend, 0)
        XCTAssertEqual(s.schemaVersion, 1)
    }

    // MARK: - Task 2: derive pre-account branches

    func testDeriveHardRevocationOverridesEverything() async throws {
        var s = EntitlementState(account: makeSnapshot(), lastVerifiedAt: Date())
        s.lastError = .revoked
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.revoked))
        XCTAssertEqual(d.cta, .reenterCode)
    }

    func testDerivePlatformNotConfigured() async throws {
        let s = EntitlementState(account: makeSnapshot())
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: false)
        XCTAssertEqual(d.capability, .readOnly(.platformNotConfigured))
        XCTAssertEqual(d.cta, .configurePlatform)
    }

    func testDeriveNoAccount() async throws {
        let s = EntitlementState()
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.noAccount))
        XCTAssertEqual(d.cta, .activate)
    }

    func testDeriveBootstrappingWhenPendingAndNoAccount() async throws {
        let s = EntitlementState(pending: .offlineCode(OfflineCode(raw: "X", issuedAt: Date())))
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .bootstrapping)
        XCTAssertNil(d.cta)
    }

    // MARK: - Task 3: derive snapshot branches

    func testDeriveRevokedKeyLocks() async throws {
        let s = EntitlementState(account: makeSnapshot(keyState: .revoked), lastVerifiedAt: Date())
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.revoked))
        XCTAssertEqual(d.cta, .reenterCode)
    }

    func testDerivePausedAccountLocks() async throws {
        let s = EntitlementState(account: makeSnapshot(accountState: .paused), lastVerifiedAt: Date())
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.revoked))
    }

    func testDeriveExpiredByServerState() async throws {
        let s = EntitlementState(account: makeSnapshot(accountState: .expired), lastVerifiedAt: Date())
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.expired))
        XCTAssertEqual(d.cta, .renew)
    }

    func testDeriveExpiredByCreditExpiry() async throws {
        let past = Date(timeIntervalSince1970: 1_000)
        let s = EntitlementState(account: makeSnapshot(creditExpiresAt: past), lastVerifiedAt: Date())
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.expired))
    }

    func testDeriveExhaustedAfterLocalSpend() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 50), lastVerifiedAt: Date())
        s.localSpend = 50  // effective = 0
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.exhausted))
        XCTAssertEqual(d.cta, .renew)
    }

    func testDeriveGraceElapsed() async throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let s = EntitlementState(account: makeSnapshot(), lastVerifiedAt: old)
        let now = old.addingTimeInterval(EntitlementEngine.defaultGraceWindow + 1)
        let d = EntitlementEngine.derive(s, now: now, platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.offlineGraceElapsed))
        XCTAssertEqual(d.cta, .goOnline)
    }

    func testDeriveReadyWithinGrace() async throws {
        let lv = Date(timeIntervalSince1970: 1_000)
        let s = EntitlementState(account: makeSnapshot(creditBalance: 500), lastVerifiedAt: lv)
        let now = lv.addingTimeInterval(EntitlementEngine.defaultGraceWindow - 1)
        let d = EntitlementEngine.derive(s, now: now, platformConfigured: true)
        XCTAssertEqual(d.capability, .ready)
        XCTAssertEqual(d.availableModels, ["gemini-3-flash-preview"])
        XCTAssertEqual(d.credits?.balance, 500)
        XCTAssertNil(d.cta)
    }

    func testDeriveReadyReflectsLocalSpendInCredits() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 500), lastVerifiedAt: Date())
        s.localSpend = 120
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .ready)
        XCTAssertEqual(d.credits?.balance, 380)
    }

    // MARK: - Task 4: reduce refresh/reconcile/failure

    func testReduceRelayRefreshedReconcilesAndClears() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 10), localSpend: 7)
        s.lastError = .revoked
        let now = Date()
        let fresh = makeSnapshot(creditBalance: 900)
        let out = EntitlementEngine.reduce(s, .relayRefreshed(fresh, now: now))
        XCTAssertEqual(out.account, fresh)
        XCTAssertEqual(out.localSpend, 0)
        XCTAssertNil(out.lastError)
        XCTAssertEqual(out.lastVerifiedAt, now)
    }

    func testReduceRefreshClearsPendingPrecedence() async throws {
        var s = EntitlementState()
        s.pending = .offlineCode(OfflineCode(raw: "X", issuedAt: Date()))
        let out = EntitlementEngine.reduce(s, .relayRefreshed(makeSnapshot(), now: Date()))
        XCTAssertNil(out.pending)
        XCTAssertNotNil(out.account)
    }

    func testReduceSoftFailureKeepsState() async throws {
        let s = EntitlementState(account: makeSnapshot(), lastVerifiedAt: Date(timeIntervalSince1970: 1))
        let out = EntitlementEngine.reduce(s, .relayRefreshFailed(hard: nil, now: Date()))
        XCTAssertNil(out.lastError)
        XCTAssertEqual(out.account, s.account)
    }

    func testReduceHardFailureSetsLastError() async throws {
        let s = EntitlementState(account: makeSnapshot())
        let out = EntitlementEngine.reduce(s, .relayRefreshFailed(hard: .revoked, now: Date()))
        XCTAssertEqual(out.lastError, .revoked)
    }

    // MARK: - Task 5: remaining reduce events end-to-end

    func testOptimisticSpendThenDeriveExhausts() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 30), lastVerifiedAt: Date())
        s = EntitlementEngine.reduce(s, .messageConsumed(cost: 30))
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.exhausted))
    }

    func testPendingOnlySetWhenNoAccount() async throws {
        let s = EntitlementState(account: makeSnapshot())
        let out = EntitlementEngine.reduce(s, .offlineCodeEntered(OfflineCode(raw: "X", issuedAt: Date())))
        XCTAssertNil(out.pending)
    }

    func testPairedTokenSetsPendingBootstrapping() async throws {
        let s = EntitlementState()
        let out = EntitlementEngine.reduce(s, .pairedTokenReceived(PairingToken(token: "T", issuedAt: Date())))
        let d = EntitlementEngine.derive(out, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .bootstrapping)
    }

    func testSignedOutResetsToNoAccount() async throws {
        var s = EntitlementState(account: makeSnapshot(), lastVerifiedAt: Date(), localSpend: 99)
        s.lastError = .revoked
        let out = EntitlementEngine.reduce(s, .signedOut)
        XCTAssertEqual(out, EntitlementState())
        let d = EntitlementEngine.derive(out, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.noAccount))
    }

    func testPurchaseAppliedBecomesReady() async throws {
        let s = EntitlementState()
        let out = EntitlementEngine.reduce(s, .purchaseApplied(makeSnapshot(creditBalance: 5000), now: Date()))
        let d = EntitlementEngine.derive(out, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .ready)
        XCTAssertEqual(d.credits?.balance, 5000)
    }

    // MARK: - Task 6: projection from wire types

    func testProjectionMapsAccountKeyAndRates() async throws {
        let account = RelayAccountSummary(
            accountID: UUID(), displayName: nil, adminNote: nil,
            state: .active, source: .subscription, planID: "flash_monthly",
            originalTransactionID: nil, appAccountToken: nil,
            creditBalance: 1234, creditExpiresAt: nil, lastUsageAt: nil
        )
        let key = RelayKeySummary(
            keyID: UUID(), keyValue: "rk_live", state: .active,
            source: .subscription, note: nil, issuedAt: Date()
        )
        let rate = RelayMeteringRate(
            modelID: "gemini-3-flash-preview",
            inputCreditsPerMillion: 100, inputCreditsPerMillionOver200k: nil,
            outputCreditsPerMillion: 300, outputCreditsPerMillionOver200k: nil,
            audioInputCreditsPerMillion: nil,
            searchSurchargeCredits: 14
        )
        let snap = EntitlementEngine.project(account: account, key: key, rates: [rate])
        XCTAssertEqual(snap.creditBalance, 1234)
        XCTAssertEqual(snap.keyValue, "rk_live")
        XCTAssertEqual(snap.availableModels, ["gemini-3-flash-preview"])
        XCTAssertEqual(snap.rates["gemini-3-flash-preview"]?.outputCreditsPerMillion, 300)
    }

    // MARK: - Task 7: cost estimation

    func testEstimatedCostUsesRatesWithSearchSurcharge() async throws {
        let snap = makeSnapshot()
        let cost = EntitlementEngine.estimatedCost(
            snapshot: snap, model: "gemini-3-flash-preview",
            inputTokens: 1_000_000, outputTokens: 1_000_000, usesSearch: true
        )
        XCTAssertEqual(cost, 100 + 300 + 14)
    }

    func testEstimatedCostUnknownModelIsZero() async throws {
        let snap = makeSnapshot()
        let cost = EntitlementEngine.estimatedCost(
            snapshot: snap, model: "no-such-model",
            inputTokens: 1_000_000, outputTokens: 0, usesSearch: false
        )
        XCTAssertEqual(cost, 0)
    }
}
