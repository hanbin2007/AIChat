//
//  ActivationBillingServiceTests.swift
//  AIChat Watch AppTests
//
//  Regression tests for the relay-mode access gating, covering the bugs where
//  expired keys still granted access and request credits were not deducted
//  because the xcconfig bearer token bypassed all server-side validation.
//

import Foundation
import XCTest
@testable import AIChat_Watch_App

@MainActor
final class ActivationBillingServiceTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRelayConfiguration(relayBearerToken: String? = nil) -> AppConfiguration {
        AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: relayBearerToken,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
    }

    private func makeService(relayBearerToken: String? = nil) -> ActivationBillingService {
        let configuration = makeRelayConfiguration(relayBearerToken: relayBearerToken)
        let rootURL = makeTemporaryRootURL(prefix: "AIChatTests-Billing")
        return ActivationBillingService(
            configuration: configuration,
            deviceIdentity: WatchDeviceIdentity(
                rawIdentifier: "test-device-\(UUID().uuidString)",
                deviceToken: 0xDEAD_BEEF_CAFE_F00D,
                displayToken: "TEST-TOKEN"
            ),
            activationRepository: ActivationRepository(configuration: configuration, rootURL: rootURL),
            relayAccessRepository: RelayAccessRepository(configuration: configuration, rootURL: rootURL),
            syncBridge: CompanionSyncBridge(isEnabled: false)
        )
    }

    private func makeStatus(
        accountState: RelayAccountState = .active,
        keyState: RelayKeyState = .active,
        creditBalance: Int = 100,
        creditExpiresAt: Date? = nil
    ) -> RelayAccountStatusResponse {
        RelayAccountStatusResponse(
            account: RelayAccountSummary(
                accountID: UUID(),
                displayName: nil,
                adminNote: nil,
                state: accountState,
                source: .subscription,
                planID: nil,
                originalTransactionID: nil,
                appAccountToken: nil,
                creditBalance: creditBalance,
                creditExpiresAt: creditExpiresAt,
                lastUsageAt: nil
            ),
            device: nil,
            key: RelayKeySummary(
                keyID: UUID(),
                keyValue: "server-issued-key",
                state: keyState,
                source: .subscription,
                note: nil,
                issuedAt: Date(timeIntervalSince1970: 0)
            ),
            grants: [],
            recentUsage: []
        )
    }

    // MARK: - hasManagedRelayAccess

    /// Regression: previously `relayBearerToken != nil` short-circuited the
    /// gate to `true`, letting the xcconfig dev/Mac-relay token grant access
    /// even when no server-issued account existed. That caused expired keys
    /// to keep working and credits to never be deducted (no user account on
    /// the server to bill against).
    func testHasManagedRelayAccessIsFalseWhenOnlyXcconfigBearerTokenIsSet() async {
        let service = makeService(relayBearerToken: "xcconfig-admin-token")

        // No relayAccountStatus has been fetched from the server yet.
        XCTAssertNil(service.relayAccountStatus)
        XCTAssertFalse(service.hasManagedRelayAccess)
    }

    func testHasManagedRelayAccessIsTrueForActiveServerStatus() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 500,
            creditExpiresAt: Date().addingTimeInterval(3600)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertTrue(service.hasManagedRelayAccess)
    }

    func testHasManagedRelayAccessIsFalseWhenCreditsHaveExpired() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 500,
            // Server hasn't flipped state to `.expired` yet, but the credit
            // window has lapsed — the client must still deny access.
            creditExpiresAt: Date().addingTimeInterval(-60)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertFalse(service.hasManagedRelayAccess)
    }

    func testHasManagedRelayAccessIsFalseWhenAccountStateIsNotActive() async {
        let service = makeService()
        let status = makeStatus(accountState: .expired, creditBalance: 500)
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertFalse(service.hasManagedRelayAccess)
    }

    func testHasManagedRelayAccessIsFalseWhenKeyStateIsNotActive() async {
        let service = makeService()
        let status = makeStatus(keyState: .paused, creditBalance: 500)
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertFalse(service.hasManagedRelayAccess)
    }

    func testHasManagedRelayAccessIsFalseWhenCreditBalanceIsZero() async {
        let service = makeService()
        let status = makeStatus(creditBalance: 0)
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertFalse(service.hasManagedRelayAccess)
    }

    // MARK: - Status title surfaces expiration

    func testRelayAccessStatusTitleShowsExpiredEvenWhenStateIsActive() async {
        let service = makeService()
        let status = makeStatus(
            accountState: .active,
            creditBalance: 500,
            creditExpiresAt: Date().addingTimeInterval(-60)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertEqual(service.relayAccessStatusTitle, "已过期")
    }

    func testRelayAccessStatusTitleShowsAvailableWhenWithinExpiry() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 100,
            creditExpiresAt: Date().addingTimeInterval(3600)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertEqual(service.relayAccessStatusTitle, "在线可用")
    }

    // MARK: - Read-only mode follows managed access

    func testIsReadOnlyModeIsTrueWhenRelayAccessExpiredAndNoOfflineActivation() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 500,
            creditExpiresAt: Date().addingTimeInterval(-60)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        // Expired credits → not managed, and no offline activation either,
        // so the store should be locked into read-only.
        XCTAssertFalse(service.hasManagedRelayAccess)
        XCTAssertTrue(service.isReadOnlyMode)
    }
}
