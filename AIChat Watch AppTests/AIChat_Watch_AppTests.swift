//
//  AIChat_Watch_AppTests.swift
//  AIChat Watch AppTests
//
//  Created by zhb on 2026/3/7.
//

import XCTest
@testable import AIChat_Watch_App

final class AIChat_Watch_AppTests: XCTestCase {
    func testSuggestedTitleUsesCollapsedWhitespaceAndTruncates() {
        let input = "  Build   a production ready Apple Watch assistant with photo upload   "
        let title = ConversationThread.suggestedTitle(from: input)

        XCTAssertEqual(title, "Build a production ready A...")
    }

    func testContextWindowMapsRolesAndPreservesLatestMessages() {
        let imageData = Data([0x01, 0x02, 0x03])
        let attachment = ChatImageAttachment(
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            data: imageData,
            pixelWidth: 10,
            pixelHeight: 10
        )

        let messages = [
            ChatMessage(role: .user, text: "first"),
            ChatMessage(role: .assistant, text: "reply"),
            ChatMessage(role: .user, text: "latest", attachments: [attachment])
        ]

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-2.5-flash",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            ),
            session: .shared,
            maxContextMessages: 10,
            maxCharacterBudget: 1_000,
            maxInlineImageBytes: 1_000
        )
        let contents = client.contextWindow(from: messages)

        XCTAssertEqual(contents.count, 3)
        XCTAssertEqual(contents[0].role, "user")
        XCTAssertEqual(contents[1].role, "model")
        XCTAssertEqual(contents[2].role, "user")
        XCTAssertEqual(contents[2].parts.first?.text, "latest")
        XCTAssertEqual(contents[2].parts.last?.inlineData?.data, imageData.base64EncodedString())
    }

    func testGemini3RequestUsesThinkingLevel() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Explain this image")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3-flash-preview",
                thinkingIntensity: .deep
            )
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, "high")
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
    }

    func testGemini25RequestUsesThinkingBudget() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Summarize this thread")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-2.5-flash",
                thinkingIntensity: .balanced
            )
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-2.5-flash",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, 8_192)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
    }

    func testNormalizedDeltaHandlesCumulativeChunks() {
        var currentText = ""

        XCTAssertEqual(normalizedDelta(chunkText: "Hello", currentText: &currentText), "Hello")
        XCTAssertEqual(currentText, "Hello")

        XCTAssertEqual(normalizedDelta(chunkText: "Hello world", currentText: &currentText), " world")
        XCTAssertEqual(currentText, "Hello world")
    }

    func testRelayRequestCarriesThinkingOutputTokenBudget() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Write a deeper analysis")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3-flash-preview",
                thinkingIntensity: .deep
            )
        )

        let client = RelayAIClient(
            configuration: AppConfiguration(
                backendMode: .relay,
                geminiAPIKey: nil,
                geminiModel: "gemini-3-flash-preview",
                relayBaseURL: URL(string: "http://127.0.0.1:8787"),
                relayBearerToken: "token",
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = client.makeRelayRequest(for: conversation)

        XCTAssertEqual(request.maxOutputTokens, 65_536)
    }

    func testModelCatalogUsesDesktopScaleOutputBudgetForSupportedGeminiModels() {
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-3-flash-preview"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-3.1-pro-preview"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "gemini-2.5-flash"), 65_536)
        XCTAssertEqual(AIModelCatalog.maxOutputTokens(for: "custom-model"), 8_192)
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
