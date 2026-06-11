# Entitlement Core Implementation Plan (Plan 1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure, zero-IO core of the rewritten activation system — the value types and the `EntitlementEngine` state machine — fully unit-tested, with no app wiring yet.

**Architecture:** A pure functional core. `EntitlementEngine.reduce(state, event) -> state` evolves persisted state; `EntitlementEngine.derive(state, now, platformConfigured) -> EntitlementDecision` produces the single decision every consumer will read. Time is injected via parameters (replayable, exhaustively testable). A pure `RelaySnapshot` projection decouples the engine from wire Codable types.

**Tech Stack:** Swift, XCTest. watchOS target `AIChat Watch App`. Reuses existing hardened wire types in `Shared Licensing/RelayBillingContracts.swift` (`RelayAccountStatusResponse`, `RelayAccountState`, `RelayKeyState`, `RelayAccessSource`, `RelayCatalogResponse`, `RelayMeteringRate`).

**Decomposition note:** This is Plan 1 of 4. Plan 2 = `RelayClient` + `EntitlementCache` (IO/persistence/migration). Plan 3 = `EntitlementStore` orchestration + atomic `ChatStore`/Views cutover. Plan 4 = `SyncBridge` companion mirror + Keygen alignment. Each plan produces working, tested software on its own.

**Per spec:** `docs/superpowers/specs/2026-06-11-activation-entitlement-client-rewrite-design.md` (§4 decision type, §5 state machine, §6 grace/reconcile).

**watchOS test note (from CLAUDE.md):** write every test as `async throws` even when synchronous — watchOS 26 has a test-runner launch race that segfaults the first sync `@MainActor` test per process. Known-good sim: Apple Watch Series 11 (46mm) UDID `89095621-9CFA-4FD3-BB9E-1091E04D796E` (the CLAUDE.md `93A8…` UDID is absent in this environment).

---

## File Structure

| File | Responsibility |
|---|---|
| `AIChat Watch App/Entitlement/EntitlementModels.swift` | Value types: `RelaySnapshot`, `ModelRate`, `EntitlementDecision`, `LockReason`, `CreditView`, `ActionableCTA`, `PendingBootstrap`, `OfflineCode`, `PairingToken`, `RelayHardFailure`, `EntitlementState`, `EntitlementEvent` |
| `AIChat Watch App/Entitlement/EntitlementEngine.swift` | Pure `reduce`, `derive`, `estimatedCost`, and `RelaySnapshot` projection from wire types |
| `AIChat Watch AppTests/EntitlementEngineTests.swift` | Exhaustive unit tests for reduce/derive/estimatedCost/projection |

All new files must be added to the `AIChat Watch App` target and the test file to `AIChat Watch AppTests` in `AIChat.xcodeproj`.

---

## Task 1: Core value types

**Files:**
- Create: `AIChat Watch App/Entitlement/EntitlementModels.swift`
- Test: `AIChat Watch AppTests/EntitlementEngineTests.swift`

- [ ] **Step 1: Write the failing test**

Create `AIChat Watch AppTests/EntitlementEngineTests.swift`:

```swift
import XCTest
@testable import AIChat_Watch_App

final class EntitlementEngineTests: XCTestCase {
    // Helpers reused across tasks.
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -20`
Expected: FAIL to compile — `RelaySnapshot`, `EntitlementDecision`, `EntitlementState`, `ModelRate`, `ModelID` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `AIChat Watch App/Entitlement/EntitlementModels.swift`:

```swift
import Foundation

typealias ModelID = String

/// Pure projection of the server account+key+catalog, decoupled from wire Codable types.
struct RelaySnapshot: Codable, Equatable {
    var accountID: UUID
    var accountState: RelayAccountState
    var source: RelayAccessSource
    var keyValue: String
    var keyState: RelayKeyState
    var creditBalance: Int
    var creditExpiresAt: Date?
    var availableModels: [ModelID]
    var rates: [ModelID: ModelRate]
}

struct ModelRate: Codable, Equatable {
    var inputCreditsPerMillion: Int
    var outputCreditsPerMillion: Int
    var searchSurchargeCredits: Int
}

// MARK: - Decision (the single consumption outlet, spec §4)

struct EntitlementDecision: Equatable {
    enum Capability: Equatable {
        case ready
        case readOnly(LockReason)
        case bootstrapping
    }
    var capability: Capability
    var availableModels: [ModelID]
    var credits: CreditView?
    var cta: ActionableCTA?
}

enum LockReason: Equatable {
    case platformNotConfigured
    case noAccount
    case revoked
    case expired
    case exhausted
    case offlineGraceElapsed
}

struct CreditView: Equatable {
    var balance: Int            // effective = server balance - localSpend
    var expiresAt: Date?
}

enum ActionableCTA: Equatable {
    case configurePlatform
    case activate
    case reenterCode
    case renew
    case goOnline
}

// MARK: - State (persisted, spec §5)

struct OfflineCode: Codable, Equatable {
    var raw: String
    var issuedAt: Date
}

struct PairingToken: Codable, Equatable {
    var token: String
    var issuedAt: Date
}

enum PendingBootstrap: Codable, Equatable {
    case offlineCode(OfflineCode)
    case pairedToken(PairingToken)

    var issuedAt: Date {
        switch self {
        case let .offlineCode(c): return c.issuedAt
        case let .pairedToken(t): return t.issuedAt
        }
    }
}

enum RelayHardFailure: String, Codable, Equatable {
    case revoked
    case paused
    case accountMissing
}

struct EntitlementState: Codable, Equatable {
    var account: RelaySnapshot?
    var lastVerifiedAt: Date?
    var localSpend: Int
    var pending: PendingBootstrap?
    var lastError: RelayHardFailure?
    var schemaVersion: Int

    init(
        account: RelaySnapshot? = nil,
        lastVerifiedAt: Date? = nil,
        localSpend: Int = 0,
        pending: PendingBootstrap? = nil,
        lastError: RelayHardFailure? = nil,
        schemaVersion: Int = 1
    ) {
        self.account = account
        self.lastVerifiedAt = lastVerifiedAt
        self.localSpend = localSpend
        self.pending = pending
        self.lastError = lastError
        self.schemaVersion = schemaVersion
    }
}

// MARK: - Events (spec §5)

enum EntitlementEvent {
    case relayRefreshed(RelaySnapshot, now: Date)
    case relayRefreshFailed(hard: RelayHardFailure?, now: Date)  // hard != nil for 401/revoke
    case offlineCodeEntered(OfflineCode)
    case pairedTokenReceived(PairingToken)
    case exchangeSucceeded(RelaySnapshot, now: Date)
    case purchaseApplied(RelaySnapshot, now: Date)
    case messageConsumed(cost: Int)
    case signedOut
    case keyRevoked
}
```

Add both new files to the `AIChat Watch App` target and the test file to `AIChat Watch AppTests` in `AIChat.xcodeproj` (Xcode: File ▸ Add Files, or edit `project.pbxproj`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests/testDecisionEquatableAndConstructs" -only-testing:"AIChat Watch AppTests/EntitlementEngineTests/testEntitlementStateDefaults" 2>&1 | tail -15`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add "AIChat Watch App/Entitlement/EntitlementModels.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift" AIChat.xcodeproj/project.pbxproj
git commit -m "feat(entitlement): core value types for decision + state machine"
```

---

## Task 2: `derive()` — pre-account branches (platform / no-account / bootstrapping / hard failure)

**Files:**
- Create: `AIChat Watch App/Entitlement/EntitlementEngine.swift`
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append tests)

- [ ] **Step 1: Write the failing tests** — append to `EntitlementEngineTests`:

```swift
extension EntitlementEngineTests {
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -15`
Expected: FAIL — `EntitlementEngine` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `AIChat Watch App/Entitlement/EntitlementEngine.swift`:

```swift
import Foundation

enum EntitlementEngine {
    static let defaultGraceWindow: TimeInterval = 7 * 24 * 3600  // spec §13: 7 days

    static func derive(
        _ state: EntitlementState,
        now: Date,
        platformConfigured: Bool,
        graceWindow: TimeInterval = defaultGraceWindow
    ) -> EntitlementDecision {
        func lock(_ r: LockReason, _ cta: ActionableCTA?, _ credits: CreditView? = nil) -> EntitlementDecision {
            EntitlementDecision(capability: .readOnly(r), availableModels: [], credits: credits, cta: cta)
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
        // Branch 4+ implemented in Task 3.
        return EntitlementEngine.deriveWithSnapshot(snap, state: state, now: now, graceWindow: graceWindow)
    }

    // Placeholder filled in Task 3; returns ready so Task 2 tests pass.
    static func deriveWithSnapshot(
        _ snap: RelaySnapshot, state: EntitlementState, now: Date, graceWindow: TimeInterval
    ) -> EntitlementDecision {
        EntitlementDecision(capability: .ready, availableModels: snap.availableModels, credits: nil, cta: nil)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | tail -15`
Expected: PASS (all derive pre-account tests + Task 1 tests).

- [ ] **Step 5: Commit**

```bash
git add "AIChat Watch App/Entitlement/EntitlementEngine.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "feat(entitlement): derive() pre-account branches"
```

---

## Task 3: `derive()` — snapshot branches (revoked/expired/exhausted/grace/ready)

**Files:**
- Modify: `AIChat Watch App/Entitlement/EntitlementEngine.swift` (replace `deriveWithSnapshot`)
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append tests)

- [ ] **Step 1: Write the failing tests** — append:

```swift
extension EntitlementEngineTests {
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests/testDeriveRevokedKeyLocks" 2>&1 | tail -15`
Expected: FAIL — placeholder returns `.ready`, so `.readOnly(.revoked)` assertion fails.

- [ ] **Step 3: Write implementation** — replace `deriveWithSnapshot` in `EntitlementEngine.swift`:

```swift
    static func deriveWithSnapshot(
        _ snap: RelaySnapshot, state: EntitlementState, now: Date, graceWindow: TimeInterval
    ) -> EntitlementDecision {
        func lock(_ r: LockReason, _ cta: ActionableCTA?) -> EntitlementDecision {
            EntitlementDecision(capability: .readOnly(r), availableModels: [], credits: nil, cta: cta)
        }
        // Revoked/paused reported by a successful refresh (vs the 401 path in derive() branch 0).
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
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | tail -15`
Expected: PASS (all derive tests).

- [ ] **Step 5: Commit**

```bash
git add "AIChat Watch App/Entitlement/EntitlementEngine.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "feat(entitlement): derive() snapshot branches (revoked/expired/exhausted/grace/ready)"
```

---

## Task 4: `reduce()` — refresh reconcile, lastError clearing, pending precedence

**Files:**
- Modify: `AIChat Watch App/Entitlement/EntitlementEngine.swift` (add `reduce`)
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append tests)

- [ ] **Step 1: Write the failing tests** — append:

```swift
extension EntitlementEngineTests {
    func testReduceRelayRefreshedReconcilesAndClears() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 10), localSpend: 7)
        s.lastError = .revoked
        let now = Date()
        let fresh = makeSnapshot(creditBalance: 900)
        let out = EntitlementEngine.reduce(s, .relayRefreshed(fresh, now: now))
        XCTAssertEqual(out.account, fresh)        // server snapshot authoritative
        XCTAssertEqual(out.localSpend, 0)          // reconciled to zero
        XCTAssertNil(out.lastError)                // cleared on success
        XCTAssertEqual(out.lastVerifiedAt, now)
    }

    func testReduceRefreshClearsPendingPrecedence() async throws {
        var s = EntitlementState()
        s.pending = .offlineCode(OfflineCode(raw: "X", issuedAt: Date()))
        let out = EntitlementEngine.reduce(s, .relayRefreshed(makeSnapshot(), now: Date()))
        XCTAssertNil(out.pending)                  // already have access; pending dropped
        XCTAssertNotNil(out.account)
    }

    func testReduceSoftFailureKeepsState() async throws {
        let s = EntitlementState(account: makeSnapshot(), lastVerifiedAt: Date(timeIntervalSince1970: 1))
        let out = EntitlementEngine.reduce(s, .relayRefreshFailed(hard: nil, now: Date()))
        XCTAssertNil(out.lastError)                // soft failure does NOT set lastError
        XCTAssertEqual(out.account, s.account)     // cached account untouched
    }

    func testReduceHardFailureSetsLastError() async throws {
        let s = EntitlementState(account: makeSnapshot())
        let out = EntitlementEngine.reduce(s, .relayRefreshFailed(hard: .revoked, now: Date()))
        XCTAssertEqual(out.lastError, .revoked)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -15`
Expected: FAIL — `reduce` not defined.

- [ ] **Step 3: Write implementation** — add to `EntitlementEngine`:

```swift
    static func reduce(_ state: EntitlementState, _ event: EntitlementEvent) -> EntitlementState {
        var s = state
        switch event {
        case let .relayRefreshed(snap, now), let .purchaseApplied(snap, now):
            s.account = snap
            s.lastVerifiedAt = now
            s.localSpend = 0      // server balance is authoritative (spec §6 reconcile)
            s.lastError = nil
            s.pending = nil       // precedence: having access drops a pending exchange
        case let .exchangeSucceeded(snap, now):
            s.account = snap
            s.lastVerifiedAt = now
            s.localSpend = 0
            s.lastError = nil
            s.pending = nil
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
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "AIChat Watch App/Entitlement/EntitlementEngine.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "feat(entitlement): reduce() refresh reconcile + lastError + pending precedence"
```

---

## Task 5: `reduce()` — bootstrap, consume, purchase, signout (remaining events)

**Files:**
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append tests)

(Implementation already complete in Task 4's `reduce`; this task adds the missing-coverage tests and verifies end-to-end behavior including a derive after each reduce.)

- [ ] **Step 1: Write the failing-then-passing tests** — append:

```swift
extension EntitlementEngineTests {
    func testOptimisticSpendThenDeriveExhausts() async throws {
        var s = EntitlementState(account: makeSnapshot(creditBalance: 30), lastVerifiedAt: Date())
        s = EntitlementEngine.reduce(s, .messageConsumed(cost: 30))
        let d = EntitlementEngine.derive(s, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .readOnly(.exhausted))
    }

    func testPendingOnlySetWhenNoAccount() async throws {
        let s = EntitlementState(account: makeSnapshot())  // already have account
        let out = EntitlementEngine.reduce(s, .offlineCodeEntered(OfflineCode(raw: "X", issuedAt: Date())))
        XCTAssertNil(out.pending)  // ignored: account present
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
        let s = EntitlementState()  // no account
        let out = EntitlementEngine.reduce(s, .purchaseApplied(makeSnapshot(creditBalance: 5000), now: Date()))
        let d = EntitlementEngine.derive(out, now: Date(), platformConfigured: true)
        XCTAssertEqual(d.capability, .ready)
        XCTAssertEqual(d.credits?.balance, 5000)
    }
}
```

- [ ] **Step 2: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | tail -15`
Expected: PASS (these assert behavior already implemented in Task 4).

- [ ] **Step 3: Commit**

```bash
git add "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "test(entitlement): cover remaining reduce events end-to-end"
```

---

## Task 6: `RelaySnapshot` projection from wire types

**Files:**
- Modify: `AIChat Watch App/Entitlement/EntitlementEngine.swift` (add projection)
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append test)

This pure mapping turns the server's `RelayAccountStatusResponse` + `RelayCatalogResponse` into the engine's clean `RelaySnapshot`, so the engine never touches wire internals.

- [ ] **Step 1: Verify wire field names before writing the test**

Run: `grep -nE "struct RelayCatalogResponse|struct RelayMeteringPolicySnapshot|var rates|var plans|var meteringPolicy|struct RelayAccountStatusResponse|var account:|var key:" "Shared Licensing/RelayBillingContracts.swift" | head -20`
Expected: confirms `RelayCatalogResponse` exposes a metering policy with `rates: [RelayMeteringRate]`, and `RelayAccountStatusResponse` exposes `account: RelayAccountSummary?` and `key: RelayKeySummary?`. If field names differ from those used below, adjust the projection accordingly (this is the one place wire names matter).

- [ ] **Step 2: Write the failing test** — append:

```swift
extension EntitlementEngineTests {
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
            id: "gemini-3-flash-preview", modelID: "gemini-3-flash-preview",
            inputCreditsPerMillion: 100, inputCreditsPerMillionOver200k: nil,
            outputCreditsPerMillion: 300, outputCreditsPerMillionOver200k: nil,
            searchSurchargeCredits: 14
        )
        let snap = EntitlementEngine.project(account: account, key: key, rates: [rate])
        XCTAssertEqual(snap.creditBalance, 1234)
        XCTAssertEqual(snap.keyValue, "rk_live")
        XCTAssertEqual(snap.availableModels, ["gemini-3-flash-preview"])
        XCTAssertEqual(snap.rates["gemini-3-flash-preview"]?.outputCreditsPerMillion, 300)
    }
}
```

> Note: the `RelayAccountSummary`/`RelayKeySummary`/`RelayMeteringRate` initializers above use the fields confirmed in Step 1. If those types have additional required fields or different argument labels, copy the exact memberwise signature from `Shared Licensing/RelayBillingContracts.swift` and fill every field — do not omit any.

- [ ] **Step 3: Run to verify failure**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -15`
Expected: FAIL — `EntitlementEngine.project(account:key:rates:)` not defined.

- [ ] **Step 4: Write implementation** — add to `EntitlementEngine`:

```swift
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
```

- [ ] **Step 5: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests/testProjectionMapsAccountKeyAndRates" 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add "AIChat Watch App/Entitlement/EntitlementEngine.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "feat(entitlement): pure RelaySnapshot projection from wire types"
```

---

## Task 7: `estimatedCost()` — local cost estimate for optimistic spend

**Files:**
- Modify: `AIChat Watch App/Entitlement/EntitlementEngine.swift` (add `estimatedCost`)
- Modify: `AIChat Watch AppTests/EntitlementEngineTests.swift` (append test)

This keeps metering inside the entitlement layer (spec §4/§6): the store computes the `cost` for a `.messageConsumed` event from the snapshot's rates, with no second data source.

- [ ] **Step 1: Write the failing test** — append:

```swift
extension EntitlementEngineTests {
    func testEstimatedCostUsesRatesWithSearchSurcharge() async throws {
        let snap = makeSnapshot()  // flash rate: in 100/M, out 300/M, search 14
        // 1M input tokens + 1M output tokens + search on:
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
        XCTAssertEqual(cost, 0)  // unknown model: no local estimate; server reconciles authoritatively
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -15`
Expected: FAIL — `estimatedCost` not defined.

- [ ] **Step 3: Write implementation** — add to `EntitlementEngine`:

```swift
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
```

> Arithmetic check: 1_000_000 input tokens × (100 / 1_000_000) = 100.0 → rounds to 100; same for output (300). With search (+14) the test expects 100 + 300 + 14 = 414. The `.rounded()` applies to the full product (parentheses verified).

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | tail -15`
Expected: PASS (full suite).

- [ ] **Step 5: Final full-suite run + commit**

Run: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/EntitlementEngineTests" 2>&1 | grep -E "Executed|TEST"`
Expected: all green, 0 failures.

```bash
git add "AIChat Watch App/Entitlement/EntitlementEngine.swift" "AIChat Watch AppTests/EntitlementEngineTests.swift"
git commit -m "feat(entitlement): estimatedCost for optimistic local spend"
```

---

## Done criteria for Plan 1

- `EntitlementModels.swift` + `EntitlementEngine.swift` compiled into `AIChat Watch App`.
- `EntitlementEngineTests` green: all 8 `derive` branches, all `reduce` events, projection, and cost estimation covered.
- No app code reads the engine yet (wiring is Plan 3). The Watch App still builds and its existing tests still pass.

**Next:** Plan 2 — `RelayClient` (typed networking, real-JSON contract fixtures) + `EntitlementCache` (persistence, schema-versioned migration per spec §10, option B).
