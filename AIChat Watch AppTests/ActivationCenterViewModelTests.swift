//
//  ActivationCenterViewModelTests.swift
//  AIChat Watch AppTests
//
//  Drives `ActivationCenterViewModel` through `RelayActivationService`
//  with a stubbed `ActivationNetworking`. Covers the bootstrap and
//  offline-redeem flows + their error paths.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class ActivationCenterViewModelTests: XCTestCase {

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

    func test_bootstrap_setsStatusAndSuccessState() async throws {
        let networking = MockBillingNetworking()
        let response = RelayBillingFixtures.accountStatus(creditBalance: 800, keyValue: "rk_new")
        networking.onBootstrapActivation = { _ in .success(response) }

        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = ActivationCenterViewModel(service: service, appGroupIdentifier: suiteName)

        await vm.bootstrap()

        XCTAssertEqual(vm.bootstrapState, .success)
        XCTAssertEqual(vm.currentBearerKey, "rk_new")
        XCTAssertEqual(vm.creditBalance, 800)
    }

    func test_bootstrap_failureSurfacesError() async throws {
        let networking = MockBillingNetworking()
        networking.onBootstrapActivation = { _ in .failure(MockError.forced("network down")) }

        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = ActivationCenterViewModel(service: service, appGroupIdentifier: suiteName)

        await vm.bootstrap()

        guard case let .failed(message) = vm.bootstrapState else {
            return XCTFail("expected failed state")
        }
        XCTAssertTrue(message.contains("network down"))
        XCTAssertNil(vm.currentBearerKey)
    }

    func test_redeemOffline_passesPayloadAndUpdatesStatus() async throws {
        let networking = MockBillingNetworking()
        var observedPayload: RelayOfflineExchangeRequest?
        networking.onExchangeOffline = { payload in
            observedPayload = payload
            return .success(RelayBillingFixtures.accountStatus(creditBalance: 1_500, keyValue: "rk_offline"))
        }

        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity(id: "watch-42")
        )
        let vm = ActivationCenterViewModel(service: service, appGroupIdentifier: suiteName)

        await vm.redeemOffline(
            code: "ACME-1234",
            creditsTotal: 5_000,
            creditsRemaining: 5_000,
            validUntil: nil,
            allowedModelIDs: ["gemini-3-flash-preview"],
            fingerprint: "fp"
        )

        XCTAssertEqual(vm.offlineRedeemState, .success)
        XCTAssertEqual(vm.creditBalance, 1_500)
        XCTAssertEqual(observedPayload?.activationCode, "ACME-1234")
        XCTAssertEqual(observedPayload?.deviceID, "watch-42")
        XCTAssertEqual(observedPayload?.creditsTotal, 5_000)
        XCTAssertEqual(observedPayload?.allowedModelIDs, ["gemini-3-flash-preview"])
        XCTAssertEqual(observedPayload?.activationFingerprint, "fp")
    }

    func test_refreshStatus_keepsPriorStatusOnFailure() async throws {
        let networking = MockBillingNetworking()
        networking.onBootstrapActivation = { _ in .success(RelayBillingFixtures.accountStatus(creditBalance: 800)) }
        networking.onAccountStatus = { .failure(MockError.forced("offline")) }

        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = ActivationCenterViewModel(service: service, appGroupIdentifier: suiteName)
        await vm.bootstrap()
        XCTAssertEqual(vm.creditBalance, 800)

        await vm.refreshStatus()

        // Failure with cached status: balance preserved, bootstrap state
        // not flipped to failure.
        XCTAssertEqual(vm.creditBalance, 800)
        XCTAssertEqual(vm.bootstrapState, .success)
    }
}
