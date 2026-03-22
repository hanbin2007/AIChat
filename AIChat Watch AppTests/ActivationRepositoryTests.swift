//
//  ActivationRepositoryTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/3/20.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class ActivationRepositoryTests: XCTestCase {
    func testSaveLoadAndClearActivationStatePersistsAcrossRestart() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let repository = ActivationRepository(rootURL: rootURL)
        let now = Date(timeIntervalSince1970: 1_762_400_000)
        let deviceToken = OfflineActivation.deviceToken(for: "ACTIVATION-REPOSITORY-TEST")
        let state = OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: deviceToken,
                requestIssuedAt: now,
                validFrom: now,
                validUntil: now.addingTimeInterval(7 * 24 * 60 * 60),
                messageLimit: 12,
                modelMask: LicensedModelCatalog.mask(for: ["gemini-3.1-pro-preview"])
            ),
            activationCodeFingerprint: "swiftdata-test",
            activatedAt: now,
            usedMessageCount: 3
        )

        XCTAssertNil(repository.loadState())
        try repository.saveState(state)
        XCTAssertEqual(repository.loadState(), state)

        let restartedRepository = ActivationRepository(rootURL: rootURL)
        XCTAssertEqual(restartedRepository.loadState(), state)

        try restartedRepository.clearState()
        XCTAssertNil(restartedRepository.loadState())

        let restartedAgainRepository = ActivationRepository(rootURL: rootURL)
        XCTAssertNil(restartedAgainRepository.loadState())
    }

    func testFallbackIdentifierPersistsAcrossRestart() {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let repository = ActivationRepository(rootURL: rootURL)

        let firstIdentifier = repository.loadOrCreateFallbackIdentifier()
        XCTAssertFalse(firstIdentifier.isEmpty)
        XCTAssertEqual(repository.loadOrCreateFallbackIdentifier(), firstIdentifier)

        let restartedRepository = ActivationRepository(rootURL: rootURL)
        XCTAssertEqual(restartedRepository.loadOrCreateFallbackIdentifier(), firstIdentifier)
    }

    func testRelayAccessStatePersistsAcrossRestart() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivationRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let repository = RelayAccessRepository(rootURL: rootURL)
        let now = Date(timeIntervalSince1970: 1_762_400_500)
        let status = RelayAccountStatusResponse(
            account: RelayAccountSummary(
                accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000501") ?? UUID(),
                displayName: "Primary Watch",
                adminNote: "Trial access",
                state: .active,
                source: .trial,
                planID: "relay.monthly",
                originalTransactionID: nil,
                appAccountToken: nil,
                creditBalance: 120,
                creditExpiresAt: now.addingTimeInterval(30 * 24 * 60 * 60),
                lastUsageAt: now
            ),
            device: RelayDeviceSummary(
                deviceID: "WATCH-RELAY-DEVICE",
                platform: .watch,
                alias: "Series 11",
                note: nil,
                keyID: UUID(uuidString: "00000000-0000-0000-0000-000000000502"),
                lastSeenAt: now
            ),
            key: RelayKeySummary(
                keyID: UUID(uuidString: "00000000-0000-0000-0000-000000000503") ?? UUID(),
                keyValue: "relay-key-123",
                state: .active,
                source: .trial,
                note: nil,
                issuedAt: now
            ),
            grants: [
                RelayGrantSummary(
                    grantID: UUID(uuidString: "00000000-0000-0000-0000-000000000504") ?? UUID(),
                    source: .trial,
                    totalCredits: 120,
                    remainingCredits: 120,
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60),
                    note: nil
                )
            ],
            recentUsage: []
        )

        let initialState = await repository.loadState()
        XCTAssertNil(initialState)
        try await repository.saveStatus(status)
        let persistedState = await repository.loadState()
        XCTAssertEqual(persistedState?.status, status)

        let restartedRepository = RelayAccessRepository(rootURL: rootURL)
        let restartedState = await restartedRepository.loadState()
        XCTAssertEqual(restartedState?.status, status)

        try await restartedRepository.clear()
        let clearedState = await restartedRepository.loadState()
        XCTAssertNil(clearedState)
    }

    func testRelayAccountStatusResponseDecodesWhenOptionalCollectionsAreMissing() throws {
        let json =
            """
            {
              "account": {
                "account_id": "00000000-0000-0000-0000-000000000601",
                "state": "active",
                "source": "trial",
                "credit_balance": 48
              },
              "device": {
                "device_id": "WATCH-RELAY-DEVICE",
                "platform": "watch"
              },
              "key": {
                "key_id": "00000000-0000-0000-0000-000000000602",
                "key_value": "relay-key-compat",
                "state": "active",
                "source": "trial",
                "issued_at": 764553600
              }
            }
            """

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let status = try decoder.decode(RelayAccountStatusResponse.self, from: Data(json.utf8))
        XCTAssertEqual(status.account?.creditBalance, 48)
        XCTAssertEqual(status.device?.deviceID, "WATCH-RELAY-DEVICE")
        XCTAssertEqual(status.key?.keyValue, "relay-key-compat")
        XCTAssertTrue(status.grants.isEmpty)
        XCTAssertTrue(status.recentUsage.isEmpty)
    }
}
