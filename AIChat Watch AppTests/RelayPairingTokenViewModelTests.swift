//
//  RelayPairingTokenViewModelTests.swift
//  AIChat Watch AppTests
//
//  Drives `RelayPairingTokenViewModel` through `RelayActivationService`.
//  Asserts state transitions and the derived `remainingTime`/`isExpired`
//  computeds against an injected `now` clock.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class RelayPairingTokenViewModelTests: XCTestCase {

    func test_issueNewToken_populatesTokenAndExpiry() async throws {
        let networking = MockBillingNetworking()
        let issuedAt = Date(timeIntervalSince1970: 1_000_000)
        let expiresAt = issuedAt.addingTimeInterval(600)
        networking.onIssuePairingToken = {
            .success(RelayPairingTokenResponse(pairingToken: "abc-123", expiresAt: expiresAt))
        }
        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = RelayPairingTokenViewModel(service: service, now: { issuedAt })

        await vm.issueNewToken()

        XCTAssertEqual(vm.loadState, .ready)
        XCTAssertEqual(vm.token, "abc-123")
        XCTAssertEqual(vm.expiresAt, expiresAt)
        XCTAssertEqual(vm.remainingTime, 600)
        XCTAssertFalse(vm.isExpired)
    }

    func test_issueNewToken_failureSurfacesAsFailedState() async throws {
        let networking = MockBillingNetworking()
        networking.onIssuePairingToken = { .failure(MockError.forced("rate limited")) }
        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        let vm = RelayPairingTokenViewModel(service: service)

        await vm.issueNewToken()

        guard case let .failed(message) = vm.loadState else {
            return XCTFail("expected failed state")
        }
        XCTAssertTrue(message.contains("rate limited"))
        XCTAssertNil(vm.token)
    }

    func test_remainingTime_isClampedToZeroOnceExpired() async throws {
        let networking = MockBillingNetworking()
        let issuedAt = Date(timeIntervalSince1970: 1_000_000)
        let expiresAt = issuedAt.addingTimeInterval(60)
        networking.onIssuePairingToken = {
            .success(RelayPairingTokenResponse(pairingToken: "x", expiresAt: expiresAt))
        }
        let service = RelayActivationService(
            networking: networking,
            deviceIdentity: RelayBillingFixtures.deviceIdentity()
        )
        // VM clock is 5 minutes after issuance — token should be expired.
        let vm = RelayPairingTokenViewModel(
            service: service,
            now: { issuedAt.addingTimeInterval(300) }
        )

        await vm.issueNewToken()

        XCTAssertEqual(vm.remainingTime, 0)
        XCTAssertTrue(vm.isExpired)
    }
}
