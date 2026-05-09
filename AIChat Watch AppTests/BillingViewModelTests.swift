//
//  BillingViewModelTests.swift
//  AIChat Watch AppTests
//
//  Drives `BillingViewModel` through `RelayBillingService` with a
//  closure-stubbed `BillingNetworking`. Asserts the load-state machine
//  and the `lowBalance` derivation against the catalog threshold.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class BillingViewModelTests: XCTestCase {

    func test_refresh_loadsBothCatalogAndAccount() async throws {
        let networking = MockBillingNetworking()
        let plan = RelayPlanCatalogItem(
            id: "flash_monthly",
            title: "Flash Monthly",
            productID: "com.aichat.relay.flash.monthly",
            priceUSD: Decimal(string: "4.99")!,
            monthlyCredits: 20_000
        )
        networking.onBillingCatalog = { .success(RelayBillingFixtures.catalog(plans: [plan])) }
        networking.onAccountStatus = { .success(RelayBillingFixtures.accountStatus(creditBalance: 2_500)) }

        let service = RelayBillingService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = BillingViewModel(service: service)

        await vm.refresh()

        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.balance, 2_500)
        XCTAssertEqual(vm.plans.count, 1)
        XCTAssertEqual(vm.plans.first?.id, "flash_monthly")
        XCTAssertFalse(vm.lowBalance)
    }

    func test_refresh_marksLowBalanceWhenBelowThreshold() async throws {
        let networking = MockBillingNetworking()
        networking.onBillingCatalog = {
            .success(RelayBillingFixtures.catalog(lowBalanceThreshold: 300))
        }
        networking.onAccountStatus = {
            .success(RelayBillingFixtures.accountStatus(creditBalance: 100))
        }
        let service = RelayBillingService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = BillingViewModel(service: service)

        await vm.refresh()

        XCTAssertTrue(vm.lowBalance)
    }

    func test_refresh_failureFromCatalogSurfacesError() async throws {
        let networking = MockBillingNetworking()
        networking.onBillingCatalog = { .failure(MockError.forced("catalog down")) }
        // Account fetch is best-effort inside loadSnapshot — failure of
        // catalog should still propagate as the overall failure.
        networking.onAccountStatus = { .success(RelayBillingFixtures.accountStatus()) }

        let service = RelayBillingService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = BillingViewModel(service: service)

        await vm.refresh()

        guard case let .failed(message) = vm.loadState else {
            return XCTFail("expected failed state, got \(vm.loadState)")
        }
        XCTAssertTrue(message.contains("catalog down"), "got: \(message)")
    }

    func test_refreshAccountOnly_preservesPriorCatalog() async throws {
        let networking = MockBillingNetworking()
        networking.onBillingCatalog = { .success(RelayBillingFixtures.catalog()) }
        networking.onAccountStatus = { .success(RelayBillingFixtures.accountStatus(creditBalance: 500)) }
        let service = RelayBillingService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = BillingViewModel(service: service)

        await vm.refresh()
        XCTAssertEqual(vm.balance, 500)

        networking.onAccountStatus = { .success(RelayBillingFixtures.accountStatus(creditBalance: 100)) }
        await vm.refreshAccountOnly()

        XCTAssertEqual(vm.balance, 100, "balance should reflect the latest account fetch")
        XCTAssertNotNil(vm.snapshot?.catalog, "catalog should be preserved across account-only refresh")
    }
}
