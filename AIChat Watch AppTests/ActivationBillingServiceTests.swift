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
        keyValue: String = "server-issued-key",
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
                keyValue: keyValue,
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

    func testHasManagedRelayAccessIsFalseWhenServerRedactsKeyValue() async {
        let service = makeService()
        let status = makeStatus(
            keyValue: "",
            creditBalance: 500,
            creditExpiresAt: Date().addingTimeInterval(3600)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertFalse(service.hasManagedRelayAccess)
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

        XCTAssertEqual(service.relayAccessStatusTitle, L10n.tr("relay.status.expired"))
    }

    func testRelayAccessStatusTitleShowsAvailableWhenWithinExpiry() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 100,
            creditExpiresAt: Date().addingTimeInterval(3600)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)

        XCTAssertEqual(service.relayAccessStatusTitle, L10n.tr("relay.status.available"))
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

    // MARK: - M1: relay mode authorization state machine is self-consistent

    private func makeActiveOfflineState(
        deviceToken: UInt64 = 0xDEAD_BEEF_CAFE_F00D,
        messageLimit: Int? = nil,
        usedMessageCount: Int = 0
    ) -> OfflineActivationState {
        OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: deviceToken,
                requestIssuedAt: .now,
                validFrom: .distantPast,
                validUntil: .distantFuture,
                messageLimit: messageLimit,
                modelMask: 0xFFFF
            ),
            activationCodeFingerprint: "test-fingerprint",
            activatedAt: .now,
            usedMessageCount: usedMessageCount
        )
    }

    /// Regression (M1): in relay mode, a valid OFFLINE activation must not
    /// present a freely-editable composer (`isReadOnlyMode == false`) while the
    /// send-gate (`activationFailureMessage`) rejects every send. With no
    /// managed relay access and no online account fetched yet, the two surfaces
    /// must agree: read-only + an actionable "needs online binding" message
    /// (never the old permanent "verifying…" dead-end).
    func testRelayModeOfflineActiveWithNilStatusIsConsistentlyReadOnly() async {
        let service = makeService()
        service.setActivationStateForPreview(makeActiveOfflineState())

        // Sanity: offline activation alone reports active.
        if case .active = service.activationStatus {
            // expected
        } else {
            XCTFail("Expected offline activation to be active, got \(service.activationStatus)")
        }

        // No online account fetched yet.
        XCTAssertNil(service.relayAccountStatus)
        XCTAssertFalse(service.hasManagedRelayAccess)

        // Both surfaces must agree: read-only AND every send blocked.
        XCTAssertTrue(service.isReadOnlyMode)
        let failure = service.activationFailureMessage(for: "gemini-3-flash-preview")
        XCTAssertNotNil(failure)
        XCTAssertEqual(failure, L10n.tr("relay.access.needs_online_binding"))
    }

    // MARK: - M6: offline credit is refunded on a failed/cancelled send

    func testRefundActivationMessageRestoresOfflineCredit() async {
        let service = makeService()
        service.setActivationStateForPreview(makeActiveOfflineState(messageLimit: 5))

        try? service.consumeActivationMessage(for: "gemini-3-flash-preview")
        XCTAssertEqual(service.activationState?.usedMessageCount, 1)

        service.refundActivationMessage()
        XCTAssertEqual(service.activationState?.usedMessageCount, 0)
    }

    func testRefundActivationMessageIsClampedAtZero() async {
        let service = makeService()
        service.setActivationStateForPreview(makeActiveOfflineState(messageLimit: 5))

        // Nothing consumed yet → refund must not drive the counter negative.
        service.refundActivationMessage()
        XCTAssertEqual(service.activationState?.usedMessageCount, 0)
    }

    func testRefundActivationMessageIsNoOpUnderManagedRelayAccess() async {
        let service = makeService()
        let status = makeStatus(
            creditBalance: 500,
            creditExpiresAt: Date().addingTimeInterval(3600)
        )
        await service.updateRelayAccountStatus(status, shareToCompanion: false)
        service.setActivationStateForPreview(makeActiveOfflineState(messageLimit: 5, usedMessageCount: 2))

        XCTAssertTrue(service.hasManagedRelayAccess)

        // Managed relay access is metered server-side; the local offline
        // counter must be untouched.
        service.refundActivationMessage()
        XCTAssertEqual(service.activationState?.usedMessageCount, 2)
    }
}
