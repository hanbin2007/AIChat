//
//  RelayRequestShapeTests.swift
//  AIChat Watch AppTests
//
//  Tests for `RelayAIClient.makeRelayRequest(for:)` — verifies the shape
//  of the request the watch sends to the relay server (max output tokens,
//  tool flags, stored assistant model parts).
//

import XCTest
@testable import AIChat_Watch_App

final class RelayRequestShapeTests: XCTestCase {
    func testRelayRequestCarriesThinkingOutputTokenBudget() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Write a deeper analysis")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3-flash-preview",
                thinkingIntensity: .deep
            )
        )

        let request = makeClient().makeRelayRequest(for: conversation)

        XCTAssertEqual(request.maxOutputTokens, 65_536)
        XCTAssertNil(request.systemPrompt)
        XCTAssertEqual(request.systemInstructionParts?.first?.text, AIContextAssembler.conciseSystemPrompt)
    }

    func testRelayRequestCarriesGeminiToolFlags() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Search the web and run a quick calculation.")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3-flash-preview",
                usesGoogleSearch: true,
                usesCodeExecution: true
            )
        )

        let request = makeClient().makeRelayRequest(for: conversation)

        XCTAssertTrue(request.usesGoogleSearch)
        XCTAssertTrue(request.usesCodeExecution)
    }

    func testRelayRequestCarriesStoredAssistantModelParts() {
        let storedParts = [
            GeminiPart(
                text: "Intermediate reasoning",
                inlineData: nil,
                thought: true,
                thoughtSignature: "sig-thought"
            ),
            GeminiPart(
                text: "Final answer",
                inlineData: nil,
                thought: false,
                thoughtSignature: "sig-answer"
            )
        ]
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .user, text: "Question"),
                ChatMessage(
                    role: .assistant,
                    text: "Final answer",
                    thoughtSummary: "Intermediate reasoning",
                    modelResponseParts: storedParts
                ),
                ChatMessage(role: .user, text: "Follow up")
            ],
            aiConfiguration: ConversationAIConfiguration(model: "gemini-3-flash-preview")
        )

        let request = makeClient().makeRelayRequest(for: conversation)

        XCTAssertEqual(request.messages.count, 3)
        XCTAssertEqual(request.messages[1].role, "assistant")
        XCTAssertEqual(request.messages[1].modelResponseParts, storedParts)
    }

    private func makeClient() -> RelayAIClient {
        RelayAIClient(
            configuration: AppConfiguration(
                backendMode: .relay,
                geminiAPIKey: nil,
                geminiModel: "gemini-3-flash-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: URL(string: "http://127.0.0.1:8787"),
                relayBearerToken: "token",
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )
    }
}
