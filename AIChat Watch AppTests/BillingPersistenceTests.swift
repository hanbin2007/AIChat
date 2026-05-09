//
//  BillingPersistenceTests.swift
//  AIChat Watch AppTests
//
//  Drives `BillingPersistence` against an in-memory V2 container.
//  Asserts that account/key/catalog round-trip through the cache and
//  that the singleton-row semantics hold across writes.
//

import XCTest
import SwiftData
@testable import AIChat_Watch_App

final class BillingPersistenceTests: XCTestCase {

    private func makePersistence() throws -> BillingPersistence {
        let container = try AIChatModelContainer.inMemory()
        return BillingPersistence(container: container)
    }

    func test_loadAccountSnapshot_returnsNilOnFreshStore() async throws {
        let persistence = try makePersistence()
        let snapshot = try await persistence.loadAccountSnapshot()
        XCTAssertNil(snapshot)
    }

    func test_saveAndLoadAccountStatus_roundTrips() async throws {
        let persistence = try makePersistence()
        let status = RelayBillingFixtures.accountStatus(creditBalance: 1_234, keyValue: "rk_abc")

        try await persistence.saveAccountStatus(status)
        let snapshot = try await persistence.loadAccountSnapshot()

        XCTAssertEqual(snapshot?.accountStatus?.account?.creditBalance, 1_234)
        XCTAssertNotNil(snapshot?.lastRefreshedAt)
    }

    func test_saveDeviceKey_persistsKeyValue() async throws {
        let persistence = try makePersistence()
        try await persistence.saveDeviceKey("rk_new")

        let snapshot = try await persistence.loadAccountSnapshot()
        XCTAssertEqual(snapshot?.keyValue, "rk_new")
    }

    func test_saveAccountStatus_overwritesPriorWrite() async throws {
        let persistence = try makePersistence()
        try await persistence.saveAccountStatus(RelayBillingFixtures.accountStatus(creditBalance: 100))
        try await persistence.saveAccountStatus(RelayBillingFixtures.accountStatus(creditBalance: 5_000))

        let snapshot = try await persistence.loadAccountSnapshot()
        XCTAssertEqual(snapshot?.accountStatus?.account?.creditBalance, 5_000)
    }

    func test_clearAccountCache_removesRow() async throws {
        let persistence = try makePersistence()
        try await persistence.saveAccountStatus(RelayBillingFixtures.accountStatus(creditBalance: 100))
        try await persistence.clearAccountCache()

        let snapshot = try await persistence.loadAccountSnapshot()
        XCTAssertNil(snapshot)
    }

    func test_saveAndLoadCatalog_roundTrips() async throws {
        let persistence = try makePersistence()
        let catalog = RelayBillingFixtures.catalog(lowBalanceThreshold: 250)

        try await persistence.saveCatalog(catalog)
        let snapshot = try await persistence.loadCatalog()

        XCTAssertEqual(
            snapshot?.catalog.meteringPolicy.lowBalanceThresholdCredits,
            250
        )
    }

    func test_clearCatalogCache_removesRow() async throws {
        let persistence = try makePersistence()
        try await persistence.saveCatalog(RelayBillingFixtures.catalog())
        try await persistence.clearCatalogCache()

        let snapshot = try await persistence.loadCatalog()
        XCTAssertNil(snapshot)
    }
}
