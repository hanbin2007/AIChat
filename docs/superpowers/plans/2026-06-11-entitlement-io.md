# Entitlement IO Implementation Plan (Plan 2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Build the IO seam around the pure core: a testable `RelayClient` that fetches+projects a `RelaySnapshot`, and an `EntitlementCache` that persists `EntitlementState`.

**Architecture:** `RelayClient` is a protocol (test seam) with a `LiveRelayClient` that wraps the already-hardened `RelayAccountService` (`fetchCatalog()`, `fetchAccountStatusIfPossible()`), projecting via `EntitlementEngine.project`. `EntitlementCache` is JSON-file persistence of `EntitlementState` with a schemaVersion guard. Migration (spec §10, option B) is trivial: start empty; the existing `RelayAccessRepository` keychain/app-group key store remains the bearer source, and legacy offline-only `ActivationStateRecord` is intentionally ignored (users re-activate).

**Tech Stack:** Swift, XCTest, watchOS `AIChat Watch App`. Builds on Plan 1 (`EntitlementEngine`, `RelaySnapshot`, `EntitlementState`).

**Module/import:** `@testable import AIChat_Watch_App`. Sim UDID `89095621-9CFA-4FD3-BB9E-1091E04D796E`. Tests `async throws`. Files auto-join targets (PBXFileSystemSynchronizedRootGroup) — no pbxproj edits.

**Existing context the implementer needs:**
- `RelayAccountService` (actor/`@MainActor` service) exposes `func fetchCatalog() async throws -> RelayCatalogResponse` and `func fetchAccountStatusIfPossible() async throws -> RelayAccountStatusResponse?` (returns nil when no bearer). It already throws `RelayAccountServiceError.unauthorized` on 401 (added in the recent fixes).
- `RelayAccountStatusResponse` has `account: RelayAccountSummary?` and `key: RelayKeySummary?`. `RelayCatalogResponse` exposes the metering rates; confirm the exact path to `[RelayMeteringRate]` by reading `Shared Licensing/RelayBillingContracts.swift` (look for `RelayCatalogResponse` and `RelayMeteringPolicySnapshot.rates`).
- `EntitlementEngine.project(account:key:rates:) -> RelaySnapshot` already exists (Plan 1).
- App-group container root: `BillingActivationStoreSupport.makeContainer(appGroupIdentifier:)` returns `(rootURL:, container:)`; use its `rootURL` as the directory for the cache file.

---

## Task 1: RelayError + RelayClient protocol + FakeRelayClient

**Files:**
- Create: `AIChat Watch App/Entitlement/RelayClient.swift`
- Test: `AIChat Watch AppTests/RelayClientTests.swift`

- [ ] **Step 1: Failing test** — `RelayClientTests.swift`:

```swift
import XCTest
@testable import AIChat_Watch_App

final class RelayClientTests: XCTestCase {
    func testFakeReturnsConfiguredSnapshot() async throws {
        let snap = RelaySnapshot(
            accountID: UUID(), accountState: .active, source: .subscription,
            keyValue: "rk", keyState: .active, creditBalance: 10,
            creditExpiresAt: nil, availableModels: [], rates: [:]
        )
        let fake = FakeRelayClient(result: .success(snap))
        let got = try await fake.fetchSnapshot()
        XCTAssertEqual(got, snap)
    }

    func testFakeThrowsConfiguredError() async throws {
        let fake = FakeRelayClient(result: .failure(.unauthorized))
        do { _ = try await fake.fetchSnapshot(); XCTFail("expected throw") }
        catch let e as RelayError { XCTAssertEqual(e, .unauthorized) }
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`RelayError`/`RelayClient`/`FakeRelayClient` undefined). Command: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" build-for-testing 2>&1 | tail -15`

- [ ] **Step 3: Implement** — `RelayClient.swift`:

```swift
import Foundation

enum RelayError: Error, Equatable {
    case unauthorized            // 401 / revoked key
    case decodingFailed(String)
    case transport(String)
    case server(Int)
    case notConfigured           // no bearer / relay disabled
}

protocol RelayClient: Sendable {
    /// Fetches account status + catalog and projects into a RelaySnapshot.
    /// Throws RelayError.unauthorized on 401, .notConfigured when no bearer is available.
    func fetchSnapshot() async throws -> RelaySnapshot
}

/// Test double.
struct FakeRelayClient: RelayClient {
    var result: Result<RelaySnapshot, RelayError>
    func fetchSnapshot() async throws -> RelaySnapshot {
        switch result {
        case let .success(s): return s
        case let .failure(e): throw e
        }
    }
}
```

- [ ] **Step 4: Run — expect PASS.** Command: `xcodebuild -scheme "AIChat Watch App" -destination "platform=watchOS Simulator,id=89095621-9CFA-4FD3-BB9E-1091E04D796E" test -only-testing:"AIChat Watch AppTests/RelayClientTests" 2>&1 | grep -E "TEST|Executed"`

- [ ] **Step 5: Commit** — `git add "AIChat Watch App/Entitlement/RelayClient.swift" "AIChat Watch AppTests/RelayClientTests.swift" && git commit -m "feat(entitlement): RelayClient protocol + RelayError + fake"`

---

## Task 2: LiveRelayClient (wraps RelayAccountService, projects snapshot)

**Files:**
- Modify: `AIChat Watch App/Entitlement/RelayClient.swift` (add `LiveRelayClient`)
- Test: `AIChat Watch AppTests/RelayClientTests.swift` (add mapping test using a stub service)

**Context:** `RelayAccountService` is `@MainActor`. `LiveRelayClient` holds a reference and calls `fetchAccountStatusIfPossible()` + `fetchCatalog()`, maps errors to `RelayError`, and projects via `EntitlementEngine.project`. To make it testable without real networking, define a narrow protocol `RelayStatusFetching` that `RelayAccountService` conforms to, and have `LiveRelayClient` depend on that protocol.

- [ ] **Step 1: Failing test** — append:

```swift
private struct StubFetcher: RelayStatusFetching {
    var status: RelayAccountStatusResponse?
    var catalog: RelayCatalogResponse
    var statusError: Error?
    func fetchAccountStatusForEntitlement() async throws -> RelayAccountStatusResponse? {
        if let statusError { throw statusError }
        return status
    }
    func fetchCatalogForEntitlement() async throws -> RelayCatalogResponse { catalog }
}

extension RelayClientTests {
    func testLiveProjectsStatusAndCatalog() async throws {
        // Build a minimal status + catalog using real wire initializers.
        // (Implementer: copy exact initializers from RelayBillingContracts.swift; fill ALL fields.)
        let stub = StubFetcher(
            status: /* RelayAccountStatusResponse with active account+key */ TODO_status(),
            catalog: /* RelayCatalogResponse with one gemini-3-flash-preview rate */ TODO_catalog()
        )
        let live = LiveRelayClient(fetcher: stub)
        let snap = try await live.fetchSnapshot()
        XCTAssertEqual(snap.keyState, .active)
        XCTAssertTrue(snap.availableModels.contains("gemini-3-flash-preview"))
    }

    func testLiveMapsUnauthorized() async throws {
        let stub = StubFetcher(status: nil, catalog: TODO_catalog(), statusError: RelayAccountServiceError.unauthorized)
        let live = LiveRelayClient(fetcher: stub)
        do { _ = try await live.fetchSnapshot(); XCTFail() }
        catch let e as RelayError { XCTAssertEqual(e, .unauthorized) }
    }

    func testLiveNilStatusIsNotConfigured() async throws {
        let stub = StubFetcher(status: nil, catalog: TODO_catalog())
        let live = LiveRelayClient(fetcher: stub)
        do { _ = try await live.fetchSnapshot(); XCTFail() }
        catch let e as RelayError { XCTAssertEqual(e, .notConfigured) }
    }
}
```

> Implementer: replace `TODO_status()`/`TODO_catalog()` with real constructed values using the exact memberwise initializers from `Shared Licensing/RelayBillingContracts.swift`. `RelayAccountSummary` and `RelayKeySummary` have explicit `init(...)` (see Plan 1 Task 6 for their signatures). For `RelayCatalogResponse`/`RelayMeteringPolicySnapshot`, read the file for the exact field names and required fields, and fill every one — no placeholders in the final test.

- [ ] **Step 2: Run — expect FAIL** (`RelayStatusFetching`, `LiveRelayClient`, `RelayAccountServiceError` references). Command as Task 1 Step 2.

- [ ] **Step 3: Implement** — add to `RelayClient.swift`:

```swift
/// Narrow seam over RelayAccountService for testability.
protocol RelayStatusFetching: Sendable {
    func fetchAccountStatusForEntitlement() async throws -> RelayAccountStatusResponse?
    func fetchCatalogForEntitlement() async throws -> RelayCatalogResponse
}

struct LiveRelayClient: RelayClient {
    let fetcher: RelayStatusFetching

    func fetchSnapshot() async throws -> RelaySnapshot {
        let status: RelayAccountStatusResponse?
        do {
            status = try await fetcher.fetchAccountStatusForEntitlement()
        } catch let e as RelayAccountServiceError where e == .unauthorized {
            throw RelayError.unauthorized
        } catch {
            throw RelayError.transport(String(describing: error))
        }
        guard let status, let account = status.account, let key = status.key else {
            throw RelayError.notConfigured
        }
        let catalog: RelayCatalogResponse
        do { catalog = try await fetcher.fetchCatalogForEntitlement() }
        catch { throw RelayError.transport(String(describing: error)) }
        // Implementer: extract the [RelayMeteringRate] from `catalog` (read RelayCatalogResponse
        // for the exact accessor, e.g. catalog.meteringPolicy.rates). Fill the real path.
        let rates: [RelayMeteringRate] = catalog.meteringPolicy.rates
        return EntitlementEngine.project(account: account, key: key, rates: rates)
    }
}
```

> Implementer: also add the `RelayStatusFetching` conformance to `RelayAccountService` in a small extension (mapping `fetchAccountStatusForEntitlement` → existing `fetchAccountStatusIfPossible`, `fetchCatalogForEntitlement` → existing `fetchCatalog`). Confirm `RelayAccountServiceError` is `Equatable` with an `.unauthorized` case; if the `where e == .unauthorized` pattern doesn't compile, switch on the case directly. Verify `catalog.meteringPolicy.rates` is the real path; adjust if the wire type differs.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "feat(entitlement): LiveRelayClient wraps RelayAccountService + projects snapshot"`

---

## Task 3: EntitlementCache (Codable persistence + schemaVersion guard)

**Files:**
- Create: `AIChat Watch App/Entitlement/EntitlementCache.swift`
- Test: `AIChat Watch AppTests/EntitlementCacheTests.swift`

**Context:** Persist `EntitlementState` as JSON to a file `entitlement-state.json` under a directory the test can inject (so tests use a temp dir, production uses `BillingActivationStoreSupport.makeContainer(...).rootURL`). On load, if the file is missing or its `schemaVersion` != `EntitlementCache.currentSchemaVersion` (1), return nil (fresh start — this is the spec §10 migration: legacy data does not map, users re-activate).

- [ ] **Step 1: Failing test** — `EntitlementCacheTests.swift`:

```swift
import XCTest
@testable import AIChat_Watch_App

final class EntitlementCacheTests: XCTestCase {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testSaveThenLoadRoundTrips() async throws {
        let dir = try tempDir()
        let cache = EntitlementCache(directory: dir)
        var state = EntitlementState()
        state.localSpend = 42
        try cache.save(state)
        let loaded = cache.load()
        XCTAssertEqual(loaded?.localSpend, 42)
    }

    func testLoadMissingReturnsNil() async throws {
        let cache = EntitlementCache(directory: try tempDir())
        XCTAssertNil(cache.load())
    }

    func testLoadWrongSchemaReturnsNil() async throws {
        let dir = try tempDir()
        let cache = EntitlementCache(directory: dir)
        var state = EntitlementState()
        state.schemaVersion = 999
        try cache.save(state)
        XCTAssertNil(cache.load())   // schema mismatch -> fresh start (migration option B)
    }

    func testClearRemovesFile() async throws {
        let dir = try tempDir()
        let cache = EntitlementCache(directory: dir)
        try cache.save(EntitlementState())
        try cache.clear()
        XCTAssertNil(cache.load())
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`EntitlementCache` undefined).

- [ ] **Step 3: Implement** — `EntitlementCache.swift`:

```swift
import Foundation

/// JSON-file persistence of EntitlementState with a schema-version guard.
struct EntitlementCache {
    static let currentSchemaVersion = 1
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("entitlement-state.json") }

    func save(_ state: EntitlementState) throws {
        var s = state
        s.schemaVersion = Self.currentSchemaVersion
        let data = try JSONEncoder().encode(s)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() -> EntitlementState? {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(EntitlementState.self, from: data),
              state.schemaVersion == Self.currentSchemaVersion
        else { return nil }
        return state
    }

    func clear() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

> Note: `save` forces `schemaVersion = currentSchemaVersion`, so `testLoadWrongSchemaReturnsNil` must write the wrong version by bypassing `save` — adjust the test to write hand-crafted JSON with `"schemaVersion": 999` directly to `cache.fileURL`, OR change `save` to preserve the passed version. Pick the JSON-write approach in the test (keeps production `save` correct). Implementer: update that one test to `try #"{"localSpend":0,"schemaVersion":999}"#.data(using:.utf8)!.write(to: cache.fileURL)` style with all required EntitlementState keys, or encode a state then patch the field — whichever compiles cleanly given EntitlementState's Codable shape.

- [ ] **Step 4: Run — expect PASS.**

- [ ] **Step 5: Commit** — `git commit -m "feat(entitlement): EntitlementCache JSON persistence + schema guard"`

---

## Done criteria for Plan 2

- `RelayClient.swift` (protocol + `LiveRelayClient` + `FakeRelayClient` + `RelayStatusFetching`), `EntitlementCache.swift` compiled into `AIChat Watch App`.
- `RelayClientTests` + `EntitlementCacheTests` green.
- No app code wired yet (Plan 3). Watch App still builds; existing tests pass.

**Next:** Plan 3 — `EntitlementStore` (orchestrate client+cache+engine, expose `decision` + `estimatedCost`, drive bootstrap/exchange/purchase/restore), then atomic `ChatStore`/Views cutover.
