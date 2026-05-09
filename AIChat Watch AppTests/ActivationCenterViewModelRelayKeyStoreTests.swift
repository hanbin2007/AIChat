//
//  ActivationCenterViewModelRelayKeyStoreTests.swift
//  AIChat Watch AppTests
//
//  Pins the §11.1 fix: bootstrap / offline-redeem must persist the
//  device-scoped `rk_*` bearer key into `RelayKeyStore` so subsequent
//  app launches resolve it via `AppConfiguration.resolvedRelayBearerToken`.
//  Without this, every cold start would have to re-bootstrap the relay.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class ActivationCenterViewModelRelayKeyStoreTests: XCTestCase {

    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "AIChat.tests.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
        suiteName = nil
        try await super.tearDown()
    }

    func test_bootstrap_writesBearerKeyToRelayKeyStore() async throws {
        let networking = MockBillingNetworking()
        networking.onBootstrapActivation = { _ in
            .success(RelayBillingFixtures.accountStatus(creditBalance: 800, keyValue: "rk_new"))
        }
        let vm = makeViewModel(networking: networking)

        await vm.bootstrap()

        XCTAssertEqual(RelayKeyStore.load(appGroupIdentifier: suiteName), "rk_new")
    }

    func test_bootstrap_failureLeavesStoreUntouched() async throws {
        let networking = MockBillingNetworking()
        networking.onBootstrapActivation = { _ in .failure(MockError.forced("network down")) }
        let vm = makeViewModel(networking: networking)

        await vm.bootstrap()

        XCTAssertNil(RelayKeyStore.load(appGroupIdentifier: suiteName))
    }

    func test_redeemOffline_writesRotatedBearerKey() async throws {
        let networking = MockBillingNetworking()
        // Seed an existing key so we can verify it's overwritten.
        RelayKeyStore.set("rk_old", appGroupIdentifier: suiteName)
        networking.onExchangeOffline = { _ in
            .success(RelayBillingFixtures.accountStatus(creditBalance: 1_500, keyValue: "rk_offline"))
        }
        let vm = makeViewModel(networking: networking)

        await vm.redeemOffline(code: "ACME-1234")

        XCTAssertEqual(RelayKeyStore.load(appGroupIdentifier: suiteName), "rk_offline")
    }

    func test_refreshStatus_doesNotMutateStore() async throws {
        let networking = MockBillingNetworking()
        RelayKeyStore.set("rk_existing", appGroupIdentifier: suiteName)
        networking.onAccountStatus = {
            .success(RelayBillingFixtures.accountStatus(creditBalance: 800, keyValue: "rk_should_not_be_persisted"))
        }
        let vm = makeViewModel(networking: networking)

        await vm.refreshStatus()

        XCTAssertEqual(RelayKeyStore.load(appGroupIdentifier: suiteName), "rk_existing")
    }

    // MARK: - Helpers

    private func makeViewModel(networking: ActivationNetworking) -> ActivationCenterViewModel {
        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        return ActivationCenterViewModel(service: service, appGroupIdentifier: suiteName)
    }
}
