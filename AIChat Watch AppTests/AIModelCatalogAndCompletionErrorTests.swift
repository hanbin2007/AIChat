//
//  AIModelCatalogAndCompletionErrorTests.swift
//  AIChat Watch AppTests
//
//  Pure-function tests for the model catalog (output token budgets,
//  available thinking intensities). The completion-error helpers
//  (`geminiCompletionError(for:)`, `relayCompletionError(...)`) lived
//  in the deleted `GeminiAPIClient.swift` and `RelayAIClient.swift`;
//  the new `ChatService` throws `RelayClientError` directly on
//  premature stream end so there's nothing to unit-test in isolation
//  here anymore.
//

import XCTest
@testable import AIChat_Watch_App

final class AIModelCatalogAndCompletionErrorTests: XCTestCase {
    func testModelCatalogUsesDesktopScaleOutputBudgetForSupportedGeminiModels() {
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-3-flash-preview"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-3.1-pro-preview"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-2.5-flash"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "custom-model"), 8_192)
    }

    func testModelCatalogLimitsExtremeThinkingToGemini31Pro() {
        XCTAssertEqual(
            AIModelCatalog.availableThinkingIntensities(for: "gemini-3.1-pro-preview"),
            [.fast, .balanced, .deep, .extreme]
        )
        XCTAssertEqual(
            AIModelCatalog.availableThinkingIntensities(for: "gemini-3-flash-preview"),
            [.fast, .balanced, .deep]
        )
        XCTAssertEqual(
            AIModelCatalog.normalizedThinkingIntensity(.extreme, for: "gemini-3-flash-preview"),
            .deep
        )
    }
}
