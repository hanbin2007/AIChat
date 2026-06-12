//
//  TestSupport.swift
//  AIChat Watch AppTests
//
//  Shared fixtures, constants, and small helpers used across multiple test files.
//

import Foundation
import XCTest
@testable import AIChat_Watch_App

/// 1×1 transparent PNG, base64 encoded. Cheapest possible image fixture.
let onePixelPNGBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW2QAAAAASUVORK5CYII="

/// Decoded one-pixel PNG bytes.
func onePixelPNGData() throws -> Data {
    try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
}

/// Build a 1×1 PNG `ChatAttachment` suitable for repository / sync tests.
func makeOnePixelImageAttachment(
    suggestedFilename: String = "image"
) throws -> ChatAttachment {
    let data = try onePixelPNGData()
    return try ChatAttachment.makeModelGeneratedImage(
        from: data,
        mimeType: "image/png",
        suggestedFilename: suggestedFilename
    )
}

/// Returns a fresh, unique temporary directory URL. Caller is responsible for cleanup
/// (most tests rely on the OS purging the simulator temp directory between runs).
func makeTemporaryRootURL(prefix: String = "AIChatTests") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
}

/// Default `AppConfiguration` used in tests that exercise Gemini request
/// shaping helpers directly. Runtime service creation is relay-only; these
/// tests instantiate Gemini helper types explicitly and do not exercise the
/// backend factory.
func makeGeminiRequestTestConfiguration(
    geminiAPIKey: String = "test",
    geminiModel: String = "gemini-2.5-flash",
    geminiTranscriptionModel: String = "gemini-3-flash-preview"
) -> AppConfiguration {
    AppConfiguration(
        backendMode: .relay,
        geminiAPIKey: geminiAPIKey,
        geminiModel: geminiModel,
        geminiTranscriptionModel: geminiTranscriptionModel,
        relayBaseURL: nil,
        relayBearerToken: nil,
        relayStreamPath: "v1/chat/stream",
        appGroupIdentifier: nil
    )
}

/// Builds a server account-status response that grants active managed relay
/// access (active account + active key + a positive, non-expired credit
/// balance). Seeding this into a `ChatStore`'s `ActivationBillingService` is the
/// relay-mode equivalent of applying an offline activation code: it flips
/// `hasManagedRelayAccess` to `true` and `isReadOnlyMode` to `false`, so the
/// store can create conversations and send messages.
@MainActor
func makeManagedRelayAccessStatus(
    creditBalance: Int = 1_000,
    creditExpiresAt: Date? = nil
) -> RelayAccountStatusResponse {
    RelayAccountStatusResponse(
        account: RelayAccountSummary(
            accountID: UUID(),
            displayName: nil,
            adminNote: nil,
            state: .active,
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
            keyValue: "test-server-issued-key",
            state: .active,
            source: .subscription,
            note: nil,
            issuedAt: Date(timeIntervalSince1970: 0)
        ),
        grants: [],
        recentUsage: []
    )
}

@MainActor
func makeManagedRelaySnapshot(
    creditBalance: Int = 1_000,
    creditExpiresAt: Date? = nil,
    modelIDs: [String] = [
        "gemini-2.5-flash",
        "gemini-3-flash-preview",
        "gemini-3.1-pro-preview"
    ]
) -> RelaySnapshot {
    let status = makeManagedRelayAccessStatus(
        creditBalance: creditBalance,
        creditExpiresAt: creditExpiresAt
    )
    let rates = modelIDs.map { modelID in
        RelayMeteringRate(
            modelID: modelID,
            inputCreditsPerMillion: 100,
            inputCreditsPerMillionOver200k: nil,
            outputCreditsPerMillion: 300,
            outputCreditsPerMillionOver200k: nil,
            audioInputCreditsPerMillion: nil,
            searchSurchargeCredits: 14
        )
    }
    return EntitlementEngine.project(
        account: status.account!,
        key: status.key!,
        rates: rates
    )
}

/// Seeds active managed relay access into a `ChatStore` so relay-mode tests can
/// exercise generic create/send/retry behavior. Replaces the old offline
/// `applyActivationCode` setup. Both the legacy billing facade and the new
/// entitlement store are seeded so tests exercise the production consumption
/// path while the old facade continues to back billing screens.
@MainActor
func seedManagedRelayAccess(
    into store: ChatStore,
    creditBalance: Int = 1_000,
    creditExpiresAt: Date? = nil
) async {
    await store.activationBilling.seedManagedRelayAccessForTesting(
        makeManagedRelayAccessStatus(
            creditBalance: creditBalance,
            creditExpiresAt: creditExpiresAt
        )
    )
    store.entitlementStore.apply(
        .relayRefreshed(
            makeManagedRelaySnapshot(
                creditBalance: creditBalance,
                creditExpiresAt: creditExpiresAt
            ),
            now: Date()
        )
    )
}

/// Relay-mode `AppConfiguration` used by tests that build a `ChatStore` and
/// then seed managed relay access. `relayBaseURL` is non-nil so the relay
/// transcription/streaming services resolve their URLs.
func makeRelayModeAppConfiguration(
    geminiModel: String = "gemini-2.5-flash",
    geminiTranscriptionModel: String = "gemini-3-flash-preview"
) -> AppConfiguration {
    AppConfiguration(
        backendMode: .relay,
        geminiAPIKey: nil,
        geminiModel: geminiModel,
        geminiTranscriptionModel: geminiTranscriptionModel,
        relayBaseURL: URL(string: "http://127.0.0.1:8787"),
        relayBearerToken: "test-token",
        relayStreamPath: "v1/chat/stream",
        appGroupIdentifier: nil
    )
}
