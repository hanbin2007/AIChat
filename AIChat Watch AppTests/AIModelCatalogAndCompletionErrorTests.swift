//
//  AIModelCatalogAndCompletionErrorTests.swift
//  AIChat Watch AppTests
//
//  Pure-function tests for the model catalog (output token budgets,
//  available thinking intensities) and the two completion-error helpers
//  used to detect truncated / incomplete streaming responses.
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

    func testGeminiCompletionErrorRequiresTerminalFinishReason() {
        XCTAssertEqual(geminiCompletionError(for: nil), .incompleteResponse)
        XCTAssertEqual(geminiCompletionError(for: "STOP"), nil)
        XCTAssertEqual(geminiCompletionError(for: "MAX_TOKENS"), .truncated)
    }

    func testRelayCompletionErrorRequiresDoneEventAndStopFinishReason() {
        XCTAssertEqual(
            relayCompletionError(didReceiveDoneEvent: false, finishReason: "STOP"),
            .incompleteResponse
        )
        XCTAssertEqual(
            relayCompletionError(didReceiveDoneEvent: true, finishReason: "STOP"),
            nil
        )
        XCTAssertEqual(
            relayCompletionError(didReceiveDoneEvent: true, finishReason: "MAX_TOKENS"),
            .truncated
        )
    }
}
