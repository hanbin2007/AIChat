import XCTest
@testable import AIChat_Watch_App

@MainActor
final class EntitlementStoreTests: XCTestCase {

    // MARK: - Helpers

    static let fixedNow = Date(timeIntervalSince1970: 1_000_000)
    let fixedNowClosure: () -> Date = { EntitlementStoreTests.fixedNow }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func makeActiveSnapshot(creditBalance: Int = 100) -> RelaySnapshot {
        RelaySnapshot(
            accountID: UUID(),
            accountState: .active,
            source: .subscription,
            keyValue: "rk_test",
            keyState: .active,
            creditBalance: creditBalance,
            creditExpiresAt: nil,
            availableModels: ["gemini-3-flash-preview"],
            rates: [
                "gemini-3-flash-preview": ModelRate(
                    inputCreditsPerMillion: 100,
                    outputCreditsPerMillion: 300,
                    searchSurchargeCredits: 14
                )
            ]
        )
    }

    // MARK: - Tests

    func testLoadsFromCacheOnInit() async throws {
        let dir = try tempDir()
        let cache = EntitlementCache(directory: dir)
        var seedState = EntitlementState()
        seedState.localSpend = 5
        try cache.save(seedState)

        let store = EntitlementStore(
            client: FakeRelayClient(result: .failure(.notConfigured)),
            cache: cache,
            platformConfigured: true,
            now: fixedNowClosure
        )

        XCTAssertEqual(store.state.localSpend, 5)
    }

    func testRefreshSuccessBecomesReady() async throws {
        let snap = makeActiveSnapshot(creditBalance: 100)
        let store = EntitlementStore(
            client: FakeRelayClient(result: .success(snap)),
            cache: EntitlementCache(directory: try tempDir()),
            platformConfigured: true,
            now: fixedNowClosure
        )

        await store.refresh()

        XCTAssertEqual(store.decision.capability, .ready)
    }

    func testRefreshUnauthorizedLocksRevoked() async throws {
        let store = EntitlementStore(
            client: FakeRelayClient(result: .failure(.unauthorized)),
            cache: EntitlementCache(directory: try tempDir()),
            platformConfigured: true,
            now: fixedNowClosure
        )

        await store.refresh()

        XCTAssertEqual(store.decision.capability, .readOnly(.revoked))
    }

    func testRecordSpendReducesEffectiveCredits() async throws {
        let snap = makeActiveSnapshot(creditBalance: 100)
        let store = EntitlementStore(
            client: FakeRelayClient(result: .success(snap)),
            cache: EntitlementCache(directory: try tempDir()),
            platformConfigured: true,
            now: fixedNowClosure
        )

        await store.refresh()
        store.recordSpend(40)

        XCTAssertEqual(store.decision.credits?.balance, 60)
    }

    func testApplyPersistsToCache() async throws {
        let dir = try tempDir()
        let snap = makeActiveSnapshot(creditBalance: 100)
        let store = EntitlementStore(
            client: FakeRelayClient(result: .success(snap)),
            cache: EntitlementCache(directory: dir),
            platformConfigured: true,
            now: fixedNowClosure
        )

        await store.refresh()

        // Create a brand-new store pointing at the SAME cache directory.
        let store2 = EntitlementStore(
            client: FakeRelayClient(result: .failure(.notConfigured)),
            cache: EntitlementCache(directory: dir),
            platformConfigured: true,
            now: fixedNowClosure
        )

        XCTAssertNotNil(store2.state.account)
    }

    func testSignOutResetsToNoAccount() async throws {
        let snap = makeActiveSnapshot(creditBalance: 100)
        let store = EntitlementStore(
            client: FakeRelayClient(result: .success(snap)),
            cache: EntitlementCache(directory: try tempDir()),
            platformConfigured: true,
            now: fixedNowClosure
        )

        await store.refresh()
        XCTAssertEqual(store.decision.capability, .ready)

        store.signOut()

        XCTAssertEqual(store.decision.capability, .readOnly(.noAccount))
    }
}
