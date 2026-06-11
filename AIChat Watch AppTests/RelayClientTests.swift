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

// MARK: - LiveRelayClient tests

private struct StubFetcher: RelayStatusFetching {
    var statusResult: Result<RelayAccountStatusResponse?, Error>
    var catalogResult: Result<RelayCatalogResponse, Error>

    func fetchAccountStatusForEntitlement() async throws -> RelayAccountStatusResponse? {
        switch statusResult {
        case let .success(v): return v
        case let .failure(e): throw e
        }
    }

    func fetchCatalogForEntitlement() async throws -> RelayCatalogResponse {
        switch catalogResult {
        case let .success(v): return v
        case let .failure(e): throw e
        }
    }
}

extension RelayClientTests {
    // MARK: - Helpers

    private func makeAccount() -> RelayAccountSummary {
        RelayAccountSummary(
            accountID: UUID(),
            displayName: "Test User",
            adminNote: nil,
            state: .active,
            source: .subscription,
            planID: "pro",
            originalTransactionID: nil,
            appAccountToken: nil,
            creditBalance: 500,
            creditExpiresAt: nil,
            lastUsageAt: nil
        )
    }

    private func makeKey() -> RelayKeySummary {
        RelayKeySummary(
            keyID: UUID(),
            keyValue: "rk_test_abc123",
            state: .active,
            source: .subscription,
            note: nil,
            issuedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeCatalog(modelID: String) -> RelayCatalogResponse {
        let rate = RelayMeteringRate(
            modelID: modelID,
            inputCreditsPerMillion: 100,
            inputCreditsPerMillionOver200k: nil,
            outputCreditsPerMillion: 400,
            outputCreditsPerMillionOver200k: nil,
            audioInputCreditsPerMillion: nil,
            searchSurchargeCredits: 0
        )
        let policy = RelayMeteringPolicySnapshot(
            creditBudgetUSDPer1000Credits: 1.0,
            trialCredits: 100,
            trialDurationDays: 14,
            lowBalanceThresholdCredits: 50,
            maxBoundDevices: 3,
            creditMultiplier: 1.0,
            rates: [rate]
        )
        return RelayCatalogResponse(
            plans: [],
            meteringPolicy: policy
        )
    }

    private func makeStatus(account: RelayAccountSummary, key: RelayKeySummary) -> RelayAccountStatusResponse {
        RelayAccountStatusResponse(
            account: account,
            device: nil,
            key: key,
            grants: [],
            recentUsage: []
        )
    }

    // MARK: - Tests

    func testLiveProjectsStatusAndCatalog() async throws {
        let modelID = "gemini-3-flash-preview"
        let stub = StubFetcher(
            statusResult: .success(makeStatus(account: makeAccount(), key: makeKey())),
            catalogResult: .success(makeCatalog(modelID: modelID))
        )
        let client = LiveRelayClient(fetcher: stub)
        let snap = try await client.fetchSnapshot()
        XCTAssertEqual(snap.keyState, .active)
        XCTAssertTrue(snap.availableModels.contains(modelID))
    }

    func testLiveMapsUnauthorized() async throws {
        let stub = StubFetcher(
            statusResult: .failure(RelayAccountServiceError.unauthorized),
            catalogResult: .success(makeCatalog(modelID: "any"))
        )
        let client = LiveRelayClient(fetcher: stub)
        do {
            _ = try await client.fetchSnapshot()
            XCTFail("Expected throw")
        } catch let e as RelayError {
            if case .unauthorized = e { /* pass */ } else {
                XCTFail("Expected .unauthorized, got \(e)")
            }
        }
    }

    func testLiveNilStatusIsNotConfigured() async throws {
        let stub = StubFetcher(
            statusResult: .success(nil),
            catalogResult: .success(makeCatalog(modelID: "any"))
        )
        let client = LiveRelayClient(fetcher: stub)
        do {
            _ = try await client.fetchSnapshot()
            XCTFail("Expected throw")
        } catch let e as RelayError {
            if case .notConfigured = e { /* pass */ } else {
                XCTFail("Expected .notConfigured, got \(e)")
            }
        }
    }
}
