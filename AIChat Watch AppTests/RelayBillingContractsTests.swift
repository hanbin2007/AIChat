//
//  RelayBillingContractsTests.swift
//  AIChat Watch AppTests
//
//  Verifies that every RelayBillingContracts struct survives the exact
//  encode → decode round-trip used by the relay server and watch client.
//
//  Server encodes:  JSONEncoder + dateEncodingStrategy = .iso8601  (camelCase keys via custom encode)
//  Client decodes:  JSONDecoder + .convertFromSnakeCase + dateDecodingStrategy = .iso8601
//  Client encodes:  JSONEncoder + .convertToSnakeCase  (sends snake_case to server)
//  Server decodes:  JSONDecoder + dateDecodingStrategy = .iso8601  (custom init handles all key variants)
//

import Foundation
import XCTest
@testable import AIChat_Watch_App

final class RelayBillingContractsTests: XCTestCase {

    // MARK: - Encoder / Decoder helpers matching real server ↔ client paths

    /// Server-side encoder: camelCase keys (from custom encode), ISO 8601 dates
    private func serverEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Client-side decoder: convertFromSnakeCase + the production relay date
    /// strategy (millisecond/second tolerant), mirroring the real decode path.
    private func clientDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.applyRelayDateDecoding()
        return decoder
    }

    /// Client-side encoder: convertToSnakeCase (sends snake_case keys to server)
    private func clientEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    /// Server-side decoder: ISO 8601 dates (custom init handles all key variants)
    private func serverDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Plain decoder with no key strategy — tests that custom init(from:) handles camelCase keys standalone
    private func plainDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.applyRelayDateDecoding()
        return decoder
    }

    // MARK: - Round-trip: server encodes → client decodes

    private func assertServerToClientRoundTrip<T: Codable & Equatable>(
        _ original: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let serverData = try serverEncoder().encode(original)
            let clientDecoded = try clientDecoder().decode(T.self, from: serverData)
            XCTAssertEqual(clientDecoded, original, "Server→Client round-trip failed for \(T.self)", file: file, line: line)

            // Also verify plain decoder works (custom init handles camelCase keys)
            let plainDecoded = try plainDecoder().decode(T.self, from: serverData)
            XCTAssertEqual(plainDecoded, original, "Server→Client plain decoder failed for \(T.self)", file: file, line: line)
        } catch {
            XCTFail("Server→Client round-trip threw for \(T.self): \(error)", file: file, line: line)
        }
    }

    // MARK: - Round-trip: client encodes → server decodes

    private func assertClientToServerRoundTrip<T: Codable & Equatable>(
        _ original: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let clientData = try clientEncoder().encode(original)
            let serverDecoded = try serverDecoder().decode(T.self, from: clientData)
            XCTAssertEqual(serverDecoded, original, "Client→Server round-trip failed for \(T.self)", file: file, line: line)
        } catch {
            XCTFail("Client→Server round-trip threw for \(T.self): \(error)", file: file, line: line)
        }
    }

    // MARK: - Full bidirectional round-trip

    private func assertBidirectionalRoundTrip<T: Codable & Equatable>(
        _ original: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertServerToClientRoundTrip(original, file: file, line: line)
        assertClientToServerRoundTrip(original, file: file, line: line)
    }

    // MARK: - Test fixtures

    private let fixedDate = ISO8601DateFormatter().date(from: "2026-04-12T10:30:00Z")!
    private let fixedUUID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    // MARK: - Tests: Request structs (client → server)

    func testRelayActivationBootstrapRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayActivationBootstrapRequest(
                deviceID: "WATCH-ABC-123",
                platform: .watch,
                deviceAlias: "Apple Watch"
            )
        )
    }

    func testRelayActivationBootstrapRequestWithNilAlias() {
        assertClientToServerRoundTrip(
            RelayActivationBootstrapRequest(
                deviceID: "WATCH-XYZ",
                platform: .iPhone,
                deviceAlias: nil
            )
        )
    }

    func testRelayPurchasePrepareRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayPurchasePrepareRequest(
                deviceID: "DEVICE-456",
                platform: .watch
            )
        )
    }

    func testRelayPurchaseSubmitRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayPurchaseSubmitRequest(
                deviceID: "DEVICE-789",
                platform: .watch,
                transaction: RelaySubmittedTransaction(
                    transactionID: "TXN-001",
                    originalTransactionID: "ORIG-001",
                    productID: "com.aichat.pro.monthly",
                    environment: "Production",
                    signedTransactionInfo: "signed-info-payload",
                    signedRenewalInfo: "signed-renewal-payload",
                    purchaseDate: nil,
                    expirationDate: nil,
                    revokedDate: nil
                )
            )
        )
    }

    func testRelayRestorePurchasesRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayRestorePurchasesRequest(
                deviceID: "DEVICE-RESTORE",
                platform: .iPhone,
                transactions: [
                    RelaySubmittedTransaction(
                        transactionID: "TXN-R1",
                        originalTransactionID: nil,
                        productID: "com.aichat.pro",
                        environment: nil,
                        signedTransactionInfo: nil,
                        signedRenewalInfo: nil,
                        purchaseDate: nil,
                        expirationDate: nil,
                        revokedDate: nil
                    )
                ]
            )
        )
    }

    func testRelayJoinPairedRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayJoinPairedRequest(
                pairingToken: "PAIR-TOKEN-XYZ",
                deviceID: "WATCH-PAIRED",
                platform: .watch,
                deviceAlias: "Apple Watch"
            )
        )
    }

    func testRelayOfflineExchangeRequestClientToServer() {
        assertClientToServerRoundTrip(
            RelayOfflineExchangeRequest(
                activationCode: "ABCD-1234-EFGH",
                deviceID: "WATCH-OFFLINE",
                platform: .watch,
                deviceAlias: "Apple Watch",
                creditsTotal: 1000,
                creditsRemaining: 800,
                validUntil: nil,
                allowedModelIDs: ["gemini-3-flash-preview", "gemini-3.1-pro-preview"],
                activationFingerprint: "fp-abc123"
            )
        )
    }

    // MARK: - Tests: Response structs (server → client)

    func testRelayPurchasePrepareResponseServerToClient() {
        assertServerToClientRoundTrip(
            RelayPurchasePrepareResponse(
                accountID: fixedUUID,
                appAccountToken: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            )
        )
    }

    func testRelayPairingTokenResponseServerToClient() {
        assertServerToClientRoundTrip(
            RelayPairingTokenResponse(
                pairingToken: "PAIR-TOKEN-123",
                expiresAt: fixedDate
            )
        )
    }

    func testRelayAccountSummaryServerToClient() {
        assertServerToClientRoundTrip(
            RelayAccountSummary(
                accountID: fixedUUID,
                displayName: "Test Account",
                adminNote: nil,
                state: .active,
                source: .subscription,
                planID: "pro-monthly",
                originalTransactionID: "ORIG-TXN-123",
                appAccountToken: fixedUUID,
                creditBalance: 5000,
                creditExpiresAt: fixedDate,
                lastUsageAt: fixedDate
            )
        )
    }

    func testRelayDeviceSummaryServerToClient() {
        assertServerToClientRoundTrip(
            RelayDeviceSummary(
                deviceID: "DEVICE-SUMMARY",
                platform: .watch,
                alias: "Apple Watch",
                note: nil,
                keyID: fixedUUID,
                lastSeenAt: fixedDate
            )
        )
    }

    func testRelayKeySummaryServerToClient() {
        assertServerToClientRoundTrip(
            RelayKeySummary(
                keyID: fixedUUID,
                keyValue: "sk-test-key-value",
                state: .active,
                source: .trial,
                note: "Trial key",
                issuedAt: fixedDate
            )
        )
    }

    func testRelayGrantSummaryServerToClient() {
        assertServerToClientRoundTrip(
            RelayGrantSummary(
                grantID: fixedUUID,
                source: .trial,
                totalCredits: 1000,
                remainingCredits: 750,
                grantedAt: fixedDate,
                expiresAt: fixedDate,
                note: "Trial grant"
            )
        )
    }

    func testRelayUsageSummaryServerToClient() {
        assertServerToClientRoundTrip(
            RelayUsageSummary(
                requestID: fixedUUID,
                endpoint: "/v1/chat/stream",
                modelID: "gemini-3-flash-preview",
                inputTokens: 1200,
                outputTokens: 800,
                reservedCredits: 50,
                settledCredits: 45,
                searchCount: 2,
                createdAt: fixedDate
            )
        )
    }

    // MARK: - Tests: Composite response (server → client)

    func testRelayAccountStatusResponseServerToClient() {
        assertServerToClientRoundTrip(
            RelayAccountStatusResponse(
                account: RelayAccountSummary(
                    accountID: fixedUUID,
                    displayName: "Test",
                    adminNote: nil,
                    state: .active,
                    source: .trial,
                    planID: nil,
                    originalTransactionID: nil,
                    appAccountToken: nil,
                    creditBalance: 500,
                    creditExpiresAt: fixedDate,
                    lastUsageAt: nil
                ),
                device: RelayDeviceSummary(
                    deviceID: "DEV-1",
                    platform: .watch,
                    alias: "Watch",
                    note: nil,
                    keyID: fixedUUID,
                    lastSeenAt: fixedDate
                ),
                key: RelayKeySummary(
                    keyID: fixedUUID,
                    keyValue: "sk-key",
                    state: .active,
                    source: .trial,
                    note: nil,
                    issuedAt: fixedDate
                ),
                grants: [
                    RelayGrantSummary(
                        grantID: fixedUUID,
                        source: .trial,
                        totalCredits: 500,
                        remainingCredits: 450,
                        grantedAt: fixedDate,
                        expiresAt: fixedDate,
                        note: nil
                    )
                ],
                recentUsage: []
            )
        )
    }

    func testRelayPurchaseSubmissionResponseServerToClient() {
        assertServerToClientRoundTrip(
            RelayPurchaseSubmissionResponse(
                status: RelayAccountStatusResponse(
                    account: nil,
                    device: nil,
                    key: nil,
                    grants: [],
                    recentUsage: []
                )
            )
        )
    }

    // MARK: - Tests: Bidirectional (structs used in both directions)

    func testRelaySubmittedTransactionBidirectional() {
        assertBidirectionalRoundTrip(
            RelaySubmittedTransaction(
                transactionID: "TXN-BI",
                originalTransactionID: "ORIG-BI",
                productID: "com.aichat.premium",
                environment: "Sandbox",
                signedTransactionInfo: "signed-txn",
                signedRenewalInfo: "signed-renewal",
                purchaseDate: nil,
                expirationDate: nil,
                revokedDate: nil
            )
        )
    }

    // MARK: - Tests: Snake-case JSON from server (simulates older server or proxy)

    func testRelayActivationBootstrapRequestDecodesSnakeCaseJSON() throws {
        let json = Data("""
        {
            "device_id": "WATCH-SNAKE",
            "platform": "watch",
            "device_alias": "Test Watch"
        }
        """.utf8)

        let decoded = try serverDecoder().decode(RelayActivationBootstrapRequest.self, from: json)

        XCTAssertEqual(decoded.deviceID, "WATCH-SNAKE")
        XCTAssertEqual(decoded.platform, .watch)
        XCTAssertEqual(decoded.deviceAlias, "Test Watch")
    }

    func testRelayPurchasePrepareResponseDecodesSnakeCaseJSON() throws {
        let json = Data("""
        {
            "account_id": "\(fixedUUID.uuidString)",
            "app_account_token": "\(fixedUUID.uuidString)"
        }
        """.utf8)

        let decoded = try plainDecoder().decode(RelayPurchasePrepareResponse.self, from: json)

        XCTAssertEqual(decoded.accountID, fixedUUID)
        XCTAssertEqual(decoded.appAccountToken, fixedUUID)
    }

    func testRelayOfflineExchangeRequestDecodesSnakeCaseJSON() throws {
        let json = Data("""
        {
            "activation_code": "CODE-123",
            "device_id": "DEV-SNAKE",
            "platform": "iPhone",
            "device_alias": null,
            "credits_total": 500,
            "credits_remaining": 500,
            "allowed_model_ids": ["gemini-3-flash-preview"],
            "activation_fingerprint": "fp-snake"
        }
        """.utf8)

        let decoded = try serverDecoder().decode(RelayOfflineExchangeRequest.self, from: json)

        XCTAssertEqual(decoded.activationCode, "CODE-123")
        XCTAssertEqual(decoded.deviceID, "DEV-SNAKE")
        XCTAssertEqual(decoded.platform, .iPhone)
        XCTAssertNil(decoded.deviceAlias)
        XCTAssertEqual(decoded.creditsTotal, 500)
        XCTAssertEqual(decoded.allowedModelIDs, ["gemini-3-flash-preview"])
        XCTAssertEqual(decoded.activationFingerprint, "fp-snake")
    }

    func testRelaySubmittedTransactionDecodesSnakeCaseJSON() throws {
        let json = Data("""
        {
            "transaction_id": "TXN-SNAKE",
            "original_transaction_id": "ORIG-SNAKE",
            "product_id": "com.aichat.plan",
            "signed_transaction_info": "info",
            "signed_renewal_info": "renewal"
        }
        """.utf8)

        let decoded = try serverDecoder().decode(RelaySubmittedTransaction.self, from: json)

        XCTAssertEqual(decoded.transactionID, "TXN-SNAKE")
        XCTAssertEqual(decoded.originalTransactionID, "ORIG-SNAKE")
        XCTAssertEqual(decoded.productID, "com.aichat.plan")
        XCTAssertEqual(decoded.signedTransactionInfo, "info")
        XCTAssertEqual(decoded.signedRenewalInfo, "renewal")
    }

    func testRelayUsageSummaryDecodesSnakeCaseJSON() throws {
        let json = Data("""
        {
            "request_id": "\(fixedUUID.uuidString)",
            "endpoint": "/v1/chat/stream",
            "model_id": "gemini-3-flash-preview",
            "input_tokens": 100,
            "output_tokens": 200,
            "reserved_credits": 10,
            "settled_credits": 8,
            "search_count": 1,
            "created_at": "2026-04-12T10:30:00Z"
        }
        """.utf8)

        let decoded = try serverDecoder().decode(RelayUsageSummary.self, from: json)

        XCTAssertEqual(decoded.requestID, fixedUUID)
        XCTAssertEqual(decoded.modelID, "gemini-3-flash-preview")
        XCTAssertEqual(decoded.inputTokens, 100)
        XCTAssertEqual(decoded.createdAt, fixedDate)
    }

    // MARK: - Tests: camelCase with lowercase "Id" (convertFromSnakeCase output)

    func testRelayActivationBootstrapRequestDecodesCamelCaseWithLowerId() throws {
        let json = Data("""
        {
            "deviceId": "WATCH-CAMEL",
            "platform": "watch"
        }
        """.utf8)

        let decoded = try plainDecoder().decode(RelayActivationBootstrapRequest.self, from: json)

        XCTAssertEqual(decoded.deviceID, "WATCH-CAMEL")
        XCTAssertEqual(decoded.platform, .watch)
    }

    func testRelayGrantSummaryDecodesCamelCaseWithLowerId() throws {
        let json = Data("""
        {
            "grantId": "\(fixedUUID.uuidString)",
            "source": "trial",
            "totalCredits": 500,
            "remainingCredits": 500,
            "grantedAt": "2026-04-12T10:30:00Z"
        }
        """.utf8)

        let decoded = try plainDecoder().decode(RelayGrantSummary.self, from: json)

        XCTAssertEqual(decoded.grantID, fixedUUID)
        XCTAssertEqual(decoded.totalCredits, 500)
    }

    // MARK: - Tests: Date encoding/decoding consistency

    func testPairingTokenResponseDateSurvivesServerClientCycle() throws {
        let original = RelayPairingTokenResponse(
            pairingToken: "TOKEN",
            expiresAt: fixedDate
        )

        let serverData = try serverEncoder().encode(original)
        let json = String(data: serverData, encoding: .utf8)!

        // Verify server outputs ISO 8601 string, not epoch number
        XCTAssertTrue(json.contains("2026-04-12T10:30:00Z"), "Server should encode dates as ISO 8601, got: \(json)")
        XCTAssertFalse(json.contains("1744453800"), "Server should not encode dates as epoch seconds")

        let clientDecoded = try clientDecoder().decode(RelayPairingTokenResponse.self, from: serverData)
        XCTAssertEqual(clientDecoded.expiresAt, fixedDate)
    }

    func testKeySummaryIssuedAtDateSurvivesServerClientCycle() throws {
        let original = RelayKeySummary(
            keyID: fixedUUID,
            keyValue: "sk-test",
            state: .active,
            source: .subscription,
            note: nil,
            issuedAt: fixedDate
        )

        let serverData = try serverEncoder().encode(original)
        let clientDecoded = try clientDecoder().decode(RelayKeySummary.self, from: serverData)

        XCTAssertEqual(clientDecoded.issuedAt, fixedDate)
        XCTAssertEqual(clientDecoded.keyID, fixedUUID)
    }

    // MARK: - Tests: Enum cases

    func testRelayAccessSourceAllCasesRoundTrip() throws {
        for source in RelayAccessSource.allCases {
            let data = try serverEncoder().encode(source)
            let decoded = try clientDecoder().decode(RelayAccessSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }

    func testRelayAccountStateAllCasesRoundTrip() throws {
        for state in RelayAccountState.allCases {
            let data = try serverEncoder().encode(state)
            let decoded = try clientDecoder().decode(RelayAccountState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func testRelayKeyStateAllCasesRoundTrip() throws {
        for state in RelayKeyState.allCases {
            let data = try serverEncoder().encode(state)
            let decoded = try clientDecoder().decode(RelayKeyState.self, from: data)
            XCTAssertEqual(decoded, state)
        }
    }

    func testRelayDevicePlatformAllCasesRoundTrip() throws {
        for platform in RelayDevicePlatform.allCases {
            let data = try serverEncoder().encode(platform)
            let decoded = try clientDecoder().decode(RelayDevicePlatform.self, from: data)
            XCTAssertEqual(decoded, platform)
        }
    }

    // MARK: - Tests: Catalog structs

    func testRelayCatalogResponseServerToClient() {
        assertServerToClientRoundTrip(
            RelayCatalogResponse(
                plans: [
                    RelayPlanCatalogItem(
                        id: "pro-monthly",
                        title: "Pro Monthly",
                        productID: "com.aichat.pro.monthly",
                        priceUSD: 9.99,
                        monthlyCredits: 10000
                    )
                ],
                meteringPolicy: RelayMeteringPolicySnapshot(
                    creditBudgetUSDPer1000Credits: 0.01,
                    trialCredits: 500,
                    trialDurationDays: 7,
                    lowBalanceThresholdCredits: 100,
                    maxBoundDevices: 3,
                    creditMultiplier: 1.0,
                    rates: [
                        RelayMeteringRate(
                            modelID: "gemini-3-flash-preview",
                            inputCreditsPerMillion: 10,
                            inputCreditsPerMillionOver200k: nil,
                            outputCreditsPerMillion: 40,
                            outputCreditsPerMillionOver200k: nil,
                            audioInputCreditsPerMillion: nil,
                            searchSurchargeCredits: 5
                        )
                    ]
                )
            )
        )
    }

    // MARK: - Tests: H1 — millisecond ISO 8601 dates from the Next.js relay

    /// The production relay emits `Date.toISOString()` with millisecond
    /// precision. The legacy `.iso8601` strategy rejects fractional seconds on
    /// older OSes, silently nuking the whole account. The relay strategy must
    /// accept BOTH precisions.
    func testRelayDateDecodingAcceptsMillisecondPrecision() throws {
        let json = Data("""
        {
            "request_id": "\(fixedUUID.uuidString)",
            "endpoint": "/v1/chat/stream",
            "model_id": "gemini-3-flash-preview",
            "input_tokens": 100,
            "output_tokens": 200,
            "reserved_credits": 10,
            "settled_credits": 8,
            "search_count": 1,
            "created_at": "2026-06-11T03:11:30.075Z"
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayUsageSummary.self, from: json)

        let expected = ISO8601DateFormatter().date(from: "2026-06-11T03:11:30Z")!.addingTimeInterval(0.075)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRelayDateDecodingAcceptsSecondPrecision() throws {
        let json = Data("""
        {
            "request_id": "\(fixedUUID.uuidString)",
            "endpoint": "/v1/chat/stream",
            "model_id": "gemini-3-flash-preview",
            "input_tokens": 100,
            "output_tokens": 200,
            "reserved_credits": 10,
            "settled_credits": 8,
            "search_count": 1,
            "created_at": "2026-06-11T03:11:30Z"
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayUsageSummary.self, from: json)
        XCTAssertEqual(decoded.createdAt, ISO8601DateFormatter().date(from: "2026-06-11T03:11:30Z")!)
    }

    /// A full account status with a millisecond `credit_expires_at` must NOT
    /// collapse `account` to nil (the H1 failure mode).
    func testAccountStatusSurvivesMillisecondCreditExpiry() throws {
        let json = Data("""
        {
            "account": {
                "accountId": "\(fixedUUID.uuidString)",
                "state": "active",
                "source": "trial",
                "creditBalance": 800,
                "creditExpiresAt": "2026-06-18T03:11:30.075Z"
            },
            "grants": [],
            "recentUsage": []
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayAccountStatusResponse.self, from: json)
        XCTAssertNotNil(decoded.account, "account must not be nuked by a millisecond date")
        XCTAssertEqual(decoded.account?.creditBalance, 800)
        XCTAssertNotNil(decoded.account?.creditExpiresAt)
    }

    // MARK: - Tests: H5 — unknown enum values decode to .unknown, not throw

    func testUnknownAccessSourceDecodesToUnknown() throws {
        let json = Data(#""brand_new_source""#.utf8)
        let decoded = try clientDecoder().decode(RelayAccessSource.self, from: json)
        XCTAssertEqual(decoded, .unknown)
    }

    func testUnknownAccountStateDecodesToUnknown() throws {
        let json = Data(#""suspended_for_review""#.utf8)
        let decoded = try clientDecoder().decode(RelayAccountState.self, from: json)
        XCTAssertEqual(decoded, .unknown)
    }

    func testUnknownKeyStateDecodesToUnknown() throws {
        let json = Data(#""quarantined""#.utf8)
        let decoded = try clientDecoder().decode(RelayKeyState.self, from: json)
        XCTAssertEqual(decoded, .unknown)
    }

    /// A new server enum value inside `account.state` must not nuke the whole
    /// account object — it should land on `.unknown`.
    func testAccountWithUnknownStateSurvives() throws {
        let json = Data("""
        {
            "account": {
                "accountId": "\(fixedUUID.uuidString)",
                "state": "frozen_pending_audit",
                "source": "subscription",
                "creditBalance": 1234
            },
            "grants": [],
            "recentUsage": []
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayAccountStatusResponse.self, from: json)
        XCTAssertNotNil(decoded.account)
        XCTAssertEqual(decoded.account?.state, .unknown)
        XCTAssertEqual(decoded.account?.creditBalance, 1234)
    }

    // MARK: - Tests: C1 — prepare accountID optional + submission response shapes

    func testPrepareResponseDecodesWithoutAccountID() throws {
        // Production Next.js relay returns only { appAccountToken }.
        let json = Data("""
        { "appAccountToken": "\(fixedUUID.uuidString)" }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayPurchasePrepareResponse.self, from: json)
        XCTAssertNil(decoded.accountID)
        XCTAssertEqual(decoded.appAccountToken, fixedUUID)
    }

    func testPrepareResponseRoundTripWithNilAccountID() {
        assertServerToClientRoundTrip(
            RelayPurchasePrepareResponse(accountID: nil, appAccountToken: fixedUUID)
        )
    }

    /// Submission/restore response must accept a BARE AccountStatusResponse
    /// (production Next.js relay shape).
    func testSubmissionResponseDecodesBareStatus() throws {
        let json = Data("""
        {
            "account": {
                "accountId": "\(fixedUUID.uuidString)",
                "state": "active",
                "source": "subscription",
                "creditBalance": 9999
            },
            "grants": [],
            "recentUsage": []
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayPurchaseSubmissionResponse.self, from: json)
        XCTAssertEqual(decoded.status.account?.creditBalance, 9999)
        XCTAssertEqual(decoded.status.account?.source, .subscription)
    }

    /// Submission/restore response must ALSO accept the wrapped { status: ... }
    /// (legacy macOS relay shape).
    func testSubmissionResponseDecodesWrappedStatus() throws {
        let json = Data("""
        {
            "status": {
                "account": {
                    "accountId": "\(fixedUUID.uuidString)",
                    "state": "active",
                    "source": "trial",
                    "creditBalance": 42
                },
                "grants": [],
                "recentUsage": []
            }
        }
        """.utf8)

        let decoded = try clientDecoder().decode(RelayPurchaseSubmissionResponse.self, from: json)
        XCTAssertEqual(decoded.status.account?.creditBalance, 42)
        XCTAssertEqual(decoded.status.account?.source, .trial)
    }
}
