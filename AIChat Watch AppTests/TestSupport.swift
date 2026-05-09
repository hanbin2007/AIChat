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

/// Default `AppConfiguration` used in unit tests. Direct-Gemini mode
/// is gone post-rewrite; the relay-only configuration is the only
/// shape now.
func makeTestAppConfiguration(
    geminiModel: String = "gemini-3-flash-preview",
    geminiTranscriptionModel: String = "gemini-3-flash-preview",
    relayBaseURL: URL? = URL(string: "https://relay.example.com"),
    relayBearerToken: String? = "test-bearer"
) -> AppConfiguration {
    AppConfiguration(
        geminiModel: geminiModel,
        geminiTranscriptionModel: geminiTranscriptionModel,
        relayBaseURL: relayBaseURL,
        relayBearerToken: relayBearerToken,
        appGroupIdentifier: nil
    )
}
