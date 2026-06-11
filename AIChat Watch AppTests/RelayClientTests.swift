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
