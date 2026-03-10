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
            kind: .image,
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
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            ),
            session: .shared,
            maxContextMessages: 10,
            maxCharacterBudget: 1_000,
            maxInlineAttachmentBytes: 1_000
        )
        let contents = client.contextWindow(from: messages)

        XCTAssertEqual(contents.count, 3)
        XCTAssertEqual(contents[0].role, "user")
        XCTAssertEqual(contents[1].role, "model")
        XCTAssertEqual(contents[2].role, "user")
        XCTAssertEqual(contents[2].parts.first?.text, "latest")
        XCTAssertEqual(contents[2].parts.last?.inlineData?.data, imageData.base64EncodedString())
    }

    func testAudioOnlyMessageAddsHiddenPromptForGemini() {
        let audioData = Data([0x10, 0x20, 0x30])
        let attachment = try! ChatAttachment.makeRecordedAudio(
            from: audioData,
            suggestedFilename: "voice.wav",
            durationSeconds: 3.2
        )
        let messages = [ChatMessage(role: .user, text: "", attachments: [attachment])]

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3-flash-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let contents = client.contextWindow(from: messages)

        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents[0].parts.first?.text, "Listen to the attached audio, infer the user's request, and answer it directly.")
        XCTAssertEqual(contents[0].parts.last?.inlineData?.mimeType, "audio/wav")
        XCTAssertEqual(contents[0].parts.last?.inlineData?.data, audioData.base64EncodedString())
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
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertEqual(requestBody.systemInstruction?.parts.first?.text, AIContextBuilder.conciseSystemPrompt)
        XCTAssertEqual(requestBody.generationConfig.temperature, 1)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, "high")
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
    }

    func testDefaultPromptModeOmitsSystemInstruction() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Summarize this thread")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3.1-pro-preview",
                thinkingIntensity: .balanced,
                systemPromptMode: .default
            )
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertNil(requestBody.systemInstruction)
    }

    func testContextAssemblerOmitsCasualFocusWithoutOpenLoops() {
        let conversation = ConversationThread(
            title: "Dinner",
            messages: [
                ChatMessage(role: .user, text: "今晚吃什么好？")
            ],
            focusState: ConversationFocusState(
                kind: .casual,
                title: "Dinner chat",
                focusNote: "User is casually asking for dinner ideas.",
                openLoops: []
            )
        )

        let assembled = AIContextAssembler.assembleReplyContext(
            for: conversation,
            configuration: ConversationAIConfiguration(model: "gemini-3-flash-preview")
        )

        XCTAssertEqual(assembled.mode, .casual)
        XCTAssertNil(assembled.prefaceText)
    }

    func testContextAssemblerIncludesTeachingArtifactsInPreface() {
        let conversation = ConversationThread(
            title: "函数导数",
            messages: [
                ChatMessage(role: .user, text: "已知 f(x)=x^2+2x，帮我讲一下导数思路")
            ],
            focusState: ConversationFocusState(
                kind: .teaching,
                title: "导数讲解",
                focusNote: "围绕二次函数求导，已经确认要先回顾导数定义，再带学生做一步步推导。",
                openLoops: ["还要解释为什么常数项求导为 0"]
            ),
            memoryItems: [
                ConversationMemoryItem(
                    text: "学生更适合先给直观思路，再给公式化写法。",
                    keywords: ["思路", "公式"]
                )
            ],
            pinnedMemories: [
                PinnedMemoryItem(
                    text: "用户是高中理科中文教学场景。",
                    keywords: ["高中", "理科", "教学"],
                    scope: .conversation
                )
            ],
            archiveSegments: [
                ConversationArchiveSegment(
                    title: "上一次函数题",
                    summary: "之前已经讲过一次单调性判断，学生在符号书写上容易漏掉定义域。",
                    keywords: ["函数", "定义域"],
                    openLoops: ["本轮还可以顺手复习定义域"],
                    sourceMessageIDs: []
                )
            ]
        )

        let assembled = AIContextAssembler.assembleReplyContext(
            for: conversation,
            configuration: ConversationAIConfiguration(model: "gemini-3-flash-preview")
        )

        XCTAssertEqual(assembled.mode, .teaching)
        XCTAssertTrue(assembled.prefaceText?.contains("Current focus:") == true)
        XCTAssertTrue(assembled.prefaceText?.contains("Pinned memory:") == true)
        XCTAssertTrue(assembled.prefaceText?.contains("Relevant conversation memory:") == true)
        XCTAssertTrue(assembled.prefaceText?.contains("Archived context:") == true)
    }

    func testCustomSystemPromptOverridesBuiltInPrompt() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Summarize this thread")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3-flash-preview",
                customSystemPrompt: "You are a strict proofreader. Return only corrected text."
            )
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3-flash-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertEqual(
            requestBody.systemInstruction?.parts.first?.text,
            "You are a strict proofreader. Return only corrected text."
        )
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
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertEqual(requestBody.generationConfig.temperature, 0.65)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, 8_192)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
    }

    func testGemini31ProExtremeUsesDynamicMaximumThinking() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Think as deeply as possible")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-3.1-pro-preview",
                thinkingIntensity: .extreme
            )
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let requestBody = client.makeRequestBody(for: conversation)

        XCTAssertNil(requestBody.generationConfig.thinkingConfig?.thinkingLevel)
        XCTAssertNil(requestBody.generationConfig.thinkingConfig?.thinkingBudget)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
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
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: URL(string: "http://127.0.0.1:8787"),
                relayBearerToken: "token",
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = client.makeRelayRequest(for: conversation)

        XCTAssertEqual(request.maxOutputTokens, 65_536)
        XCTAssertEqual(request.systemPrompt, AIContextBuilder.conciseSystemPrompt)
    }

    func testRelayModeProvidesRelayTranscriptionService() {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )

        let service = AIServiceFactory.makeTranscriptionService(configuration: configuration)

        XCTAssertNotNil(service)
        XCTAssertTrue(service is RelayTranscriptionService)
    }

    func testRelayModeRejectsHostlessBaseURLWithXcconfigHint() throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: try XCTUnwrap(URL(string: "http:/127.0.0.1:8787")),
            relayBearerToken: "token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )

        XCTAssertFalse(configuration.isAIConfigured)
        XCTAssertNil(configuration.relayStreamURL)
        XCTAssertTrue(configuration.configurationMessage.contains("http:/$()/127.0.0.1:8787"))
    }

    func testRelayModeReportsMissingBearerTokenSeparately() {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )

        XCTAssertFalse(configuration.isAIConfigured)
        XCTAssertEqual(
            configuration.configurationMessage,
            "Relay mode needs AI_RELAY_BEARER_TOKEN in Config/Secrets.xcconfig."
        )
    }

    func testRelayTranscriptionRequestUsesPromptAndAudio() throws {
        let audioData = Data([0xAA, 0xBB, 0xCC])
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: audioData,
            suggestedFilename: "voice.wav",
            durationSeconds: 4.5
        )
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .assistant, text: "Do you want the Tokyo or Osaka plan?"),
                ChatMessage(role: .user, text: "Use the Tokyo one and keep it short.")
            ]
        )
        let service = RelayTranscriptionService(
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

        let request = service.makeRelayRequest(
            for: audioAttachment,
            in: conversation,
            using: VoiceTranscriptionConfiguration(
                model: "gemini-3-flash-preview",
                customPrompt: "Product names may include Tokyo Skytree and Ginza Six.",
                includesContext: true
            )
        )

        XCTAssertEqual(request.model, "gemini-3-flash-preview")
        XCTAssertEqual(request.systemPrompt, VoiceTranscriptionPromptBuilder.systemPrompt)
        XCTAssertTrue(request.prompt.contains("Product names may include Tokyo Skytree and Ginza Six."))
        XCTAssertTrue(request.prompt.contains("Assistant: Do you want the Tokyo or Osaka plan?"))
        XCTAssertTrue(request.prompt.contains("User: Use the Tokyo one and keep it short."))
        XCTAssertEqual(request.audio.mimeType, "audio/wav")
        XCTAssertEqual(request.audio.base64Data, audioData.base64EncodedString())
    }

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

    func testTranscriptionRequestUsesContextAndAudio() throws {
        let audioData = Data([0xAA, 0xBB, 0xCC])
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: audioData,
            suggestedFilename: "voice.wav",
            durationSeconds: 4.5
        )
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .assistant, text: "Do you want the Tokyo or Osaka plan?"),
                ChatMessage(role: .user, text: "Use the Tokyo one and keep it short.")
            ]
        )

        let service = GeminiTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = service.makeRequestBody(
            for: audioAttachment,
            in: conversation,
            using: VoiceTranscriptionConfiguration(
                model: "gemini-3-flash-preview",
                customPrompt: "Expect the product name AIChat Pro.",
                includesContext: true
            )
        )

        XCTAssertEqual(request.contents.count, 1)
        XCTAssertEqual(request.generationConfig.temperature, 1)
        XCTAssertEqual(request.generationConfig.maxOutputTokens, 5_120)
        XCTAssertNil(request.generationConfig.thinkingConfig)
        XCTAssertEqual(request.contents[0].parts.last?.inlineData?.mimeType, "audio/wav")
        XCTAssertEqual(request.contents[0].parts.last?.inlineData?.data, audioData.base64EncodedString())
        XCTAssertTrue(request.contents[0].parts.first?.text?.contains("Expect the product name AIChat Pro.") == true)
        XCTAssertTrue(request.contents[0].parts.first?.text?.contains("Assistant: Do you want the Tokyo or Osaka plan?") == true)
        XCTAssertTrue(request.contents[0].parts.first?.text?.contains("User: Use the Tokyo one and keep it short.") == true)
    }

    func testTranscriptionRequestCanExcludeConversationContext() {
        let audioData = Data([0xAA, 0xBB, 0xCC])
        let audioAttachment = try! ChatAttachment.makeRecordedAudio(
            from: audioData,
            suggestedFilename: "voice.wav",
            durationSeconds: 4.5
        )
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .assistant, text: "Reminder: the project codename is Lighthouse."),
                ChatMessage(role: .user, text: "Keep that in mind.")
            ]
        )

        let service = GeminiTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = service.makeRequestBody(
            for: audioAttachment,
            in: conversation,
            using: VoiceTranscriptionConfiguration(
                model: "gemini-3-flash-preview",
                customPrompt: "The codename may be Lighthouse.",
                includesContext: false
            )
        )

        XCTAssertTrue(request.contents[0].parts.first?.text?.contains("The codename may be Lighthouse.") == true)
        XCTAssertFalse(request.contents[0].parts.first?.text?.contains("Recent conversation context:") == true)
    }

    func testGemini25TranscriptionKeepsFallbackTemperature() {
        let audioData = Data([0xAA, 0xBB, 0xCC])
        let audioAttachment = try! ChatAttachment.makeRecordedAudio(
            from: audioData,
            suggestedFilename: "voice.wav",
            durationSeconds: 4.5
        )
        let conversation = ConversationThread(messages: [])
        let service = GeminiTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = service.makeRequestBody(
            for: audioAttachment,
            in: conversation,
            using: VoiceTranscriptionConfiguration(
                model: "gemini-2.5-flash",
                customPrompt: "",
                includesContext: false
            )
        )

        XCTAssertEqual(request.generationConfig.temperature, 0.1)
    }

    func testTranscriptionResponseCanSucceedWithoutFinishReason() throws {
        let service = GeminiTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let data = Data(
            """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "帮我订明天上午去杭州的高铁" }
                    ]
                  }
                }
              ]
            }
            """.utf8
        )

        let result = try service.parseTranscriptionResponse(
            data,
            requestedModel: "gemini-3-flash-preview"
        )

        XCTAssertEqual(result.text, "帮我订明天上午去杭州的高铁")
        XCTAssertEqual(result.model, "gemini-3-flash-preview")
    }

    func testTranscriptionResponseCanDecodeLoggedGeminiPayload() throws {
        let service = GeminiTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test",
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3.1-pro-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let data = Data(
            """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "text": "但是这道题我是假设它通过两摩尔电子算的。",
                        "thoughtSignature": "abc123"
                      }
                    ],
                    "role": "model"
                  },
                  "finishReason": "STOP",
                  "index": 0
                }
              ],
              "modelVersion": "gemini-3.1-pro-preview",
              "responseId": "test-response",
              "usageMetadata": {
                "candidatesTokenCount": 13,
                "promptTokenCount": 286,
                "thoughtsTokenCount": 393,
                "totalTokenCount": 692
              }
            }
            """.utf8
        )

        let result = try service.parseTranscriptionResponse(
            data,
            requestedModel: "gemini-3.1-pro-preview"
        )

        XCTAssertEqual(result.text, "但是这道题我是假设它通过两摩尔电子算的。")
        XCTAssertEqual(result.model, "gemini-3.1-pro-preview")
    }

    func testRelayTranscriptionResponseCanDecodeWithoutModel() throws {
        let service = RelayTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .relay,
                geminiAPIKey: nil,
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: URL(string: "http://127.0.0.1:8787"),
                relayBearerToken: "test-token",
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let data = Data(
            """
            {
              "text": "book a table for four at 7 pm"
            }
            """.utf8
        )

        let result = try service.parseTranscriptionResponse(
            data,
            fallbackModel: "gemini-3-flash-preview"
        )

        XCTAssertEqual(result.text, "book a table for four at 7 pm")
        XCTAssertEqual(result.model, "gemini-3-flash-preview")
    }

    func testRelayTranscriptionResponseCanDecodeLoggedClientPayload() throws {
        let service = RelayTranscriptionService(
            configuration: AppConfiguration(
                backendMode: .relay,
                geminiAPIKey: nil,
                geminiModel: "gemini-3.1-pro-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: URL(string: "http://127.0.0.1:8787"),
                relayBearerToken: "test-token",
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let data = Data(
            """
            {
              "model": "gemini-3.1-pro-preview",
              "text": "但是这道题我是假设它通过两摩尔电子算的。"
            }
            """.utf8
        )

        let result = try service.parseTranscriptionResponse(
            data,
            fallbackModel: "gemini-3-flash-preview"
        )

        XCTAssertEqual(result.text, "但是这道题我是假设它通过两摩尔电子算的。")
        XCTAssertEqual(result.model, "gemini-3.1-pro-preview")
    }

    @MainActor
    func testRecordedAudioIsTranscribedIntoDraftWithoutSending() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: MockTranscriptionService(transcript: "Book me a train to Hangzhou tomorrow morning"),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x01, 0x02, 0x03]),
            suggestedFilename: "voice.wav",
            durationSeconds: 3.0
        )

        await store.sendRecordedAudio(audioAttachment, in: conversationID)

        let conversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertTrue(conversation.messages.isEmpty)
        XCTAssertEqual(store.draftText(for: conversationID), "Book me a train to Hangzhou tomorrow morning")
        XCTAssertNil(store.errorMessage(for: conversationID))
    }

    @MainActor
    func testRecordedAudioRetriesBeforeFailing() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let transcriptionService = FailingThenSuccessTranscriptionService(
            failuresBeforeSuccess: 2,
            transcript: "Retry transcript succeeded"
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: transcriptionService,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            sendRetryDelayNanoseconds: { _ in 0 }
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x01, 0x02, 0x03]),
            suggestedFilename: "voice.wav",
            durationSeconds: 3.0
        )

        await store.sendRecordedAudio(audioAttachment, in: conversationID)

        XCTAssertEqual(transcriptionService.callCount, 3)
        XCTAssertEqual(store.draftText(for: conversationID), "Retry transcript succeeded")
        XCTAssertNil(store.errorMessage(for: conversationID))
    }

    @MainActor
    func testSendRetryLimitDefaultsToThreeAndClampsToSupportedBounds() async throws {
        let suiteName = "AIChatTests.RetryLimit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )

        XCTAssertEqual(store.sendFailureRetryLimit, 3)

        store.updateSendFailureRetryLimit(99)
        XCTAssertEqual(store.sendFailureRetryLimit, 10)

        store.updateSendFailureRetryLimit(-2)
        XCTAssertEqual(store.sendFailureRetryLimit, 1)
    }

    @MainActor
    func testTranscriptionModelDefaultsToConfiguredValueAndPersistsSelection() async throws {
        let suiteName = "AIChatTests.TranscriptionModel.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: repositoryURL
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )

        XCTAssertEqual(store.selectedTranscriptionModel, "gemini-3-flash-preview")

        store.updateTranscriptionModel("gemini-3.1-pro-preview")
        XCTAssertEqual(store.selectedTranscriptionModel, "gemini-3.1-pro-preview")

        let reloadedStore = ChatStore(
            repository: ConversationRepository(
                configuration: configuration,
                rootURL: repositoryURL.appendingPathComponent("reload", isDirectory: true)
            ),
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )

        XCTAssertEqual(reloadedStore.selectedTranscriptionModel, "gemini-3.1-pro-preview")
    }

    @MainActor
    func testCreateConversationUsesConfiguredDefaultParameters() async throws {
        let suiteName = "AIChatTests.ConversationDefaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )

        store.updateDefaultConversationModel("gemini-3.1-pro-preview")
        store.updateDefaultConversationThinkingIntensity(.deep)
        store.updateDefaultConversationSystemPrompt("Answer like a release manager.")

        let conversationID = await store.createConversation()
        let conversation = try XCTUnwrap(store.conversation(id: conversationID))

        XCTAssertEqual(conversation.aiConfiguration?.model, "gemini-3.1-pro-preview")
        XCTAssertEqual(conversation.aiConfiguration?.thinkingIntensity, .deep)
        XCTAssertEqual(conversation.aiConfiguration?.customSystemPrompt, "Answer like a release manager.")
    }

    @MainActor
    func testRecordedAudioUsesSelectedTranscriptionModel() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let suiteName = "AIChatTests.TranscriptionSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let transcriptionService = CapturingTranscriptionService(
            transcript: "Use Gemini 3.1 Pro for this transcript"
        )
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: transcriptionService,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x01, 0x02, 0x03]),
            suggestedFilename: "voice.wav",
            durationSeconds: 3.0
        )

        store.updateTranscriptionModel("gemini-3.1-pro-preview")
        await store.sendRecordedAudio(audioAttachment, in: conversationID)

        XCTAssertEqual(transcriptionService.requestedModels, ["gemini-3.1-pro-preview"])
        XCTAssertEqual(store.draftText(for: conversationID), "Use Gemini 3.1 Pro for this transcript")
        XCTAssertNil(store.errorMessage(for: conversationID))
    }

    func testConversationRepositoryExcludesGlobalPinnedMemorySidecarFromConversationList() async throws {
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "hello")]
        )

        try await repository.save(conversation)
        try await repository.saveGlobalPinnedMemories([
            PinnedMemoryItem(
                text: "用户偏好中文回答。",
                keywords: ["中文", "回答"],
                scope: .global
            )
        ])

        let loadedConversations = try await repository.loadConversations()
        let loadedGlobalPinnedMemories = try await repository.loadGlobalPinnedMemories()

        XCTAssertEqual(loadedConversations.map(\.id), [conversation.id])
        XCTAssertEqual(loadedGlobalPinnedMemories.count, 1)
        XCTAssertEqual(loadedGlobalPinnedMemories.first?.scope, .global)
    }

    @MainActor
    func testGlobalPinnedMemoryIsInjectedOnlyWhenConversationOptsIn() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let aiService = CapturingAIStreamingService()
        let store = ChatStore(
            repository: repository,
            aiService: aiService,
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)

        let sourceConversationID = await store.createConversation()
        store.updateDraftText("记住我是高二理科生。", for: sourceConversationID)
        await store.sendMessage(in: sourceConversationID)

        let sourceConversation = try XCTUnwrap(store.conversation(id: sourceConversationID))
        let sourceMessageID = try XCTUnwrap(sourceConversation.messages.first(where: { $0.role == .user })?.id)
        await store.pinMessage(id: sourceMessageID, from: sourceConversationID, scope: .global)

        let localOnlyConversationID = await store.createConversation()
        store.updateDraftText("我们先随便聊聊。", for: localOnlyConversationID)
        await store.sendMessage(in: localOnlyConversationID)
        XCTAssertTrue(aiService.conversations.last?.pinnedMemories.isEmpty == true)

        let globalMemoryConversationID = await store.createConversation()
        await store.updateUsesGlobalPinnedMemory(true, for: globalMemoryConversationID)
        store.updateDraftText("继续聊今天的计划。", for: globalMemoryConversationID)
        await store.sendMessage(in: globalMemoryConversationID)

        let injectedPinnedMemories = aiService.conversations.last?.pinnedMemories ?? []
        XCTAssertEqual(injectedPinnedMemories.count, 1)
        XCTAssertEqual(injectedPinnedMemories.first?.scope, .global)
        XCTAssertEqual(injectedPinnedMemories.first?.text, "记住我是高二理科生。")
    }

    @MainActor
    func testSendMessageRetriesBeforeReportingFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let suiteName = "AIChatTests.SendRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let aiService = FailingThenSuccessAIStreamingService(failuresBeforeSuccess: 2)
        let store = ChatStore(
            repository: repository,
            aiService: aiService,
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults,
            sendRetryDelayNanoseconds: { _ in 0 }
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        store.updateDraftText("Retry this send", for: conversationID)

        await store.sendMessage(in: conversationID)

        let conversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(aiService.callCount, 3)
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.first?.role, .user)
        XCTAssertEqual(conversation.messages.first?.text, "Retry this send")
        XCTAssertEqual(conversation.messages.last?.role, .assistant)
        XCTAssertEqual(conversation.messages.last?.text, "Echo: Retry this send")
        XCTAssertEqual(conversation.messages.last?.status, .sent)
        XCTAssertNil(store.errorMessage(for: conversationID))
    }

    @MainActor
    func testRetryLatestReplyReplacesLatestAssistantMessage() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let aiService = SequentialReplyAIStreamingService(replies: ["First answer", "Second answer"])
        let store = ChatStore(
            repository: repository,
            aiService: aiService,
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        store.updateDraftText("Retry this answer", for: conversationID)

        await store.sendMessage(in: conversationID)
        await store.retryLatestReply(in: conversationID)

        let conversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(aiService.callCount, 2)
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.first?.role, .user)
        XCTAssertEqual(conversation.messages.first?.text, "Retry this answer")
        XCTAssertEqual(conversation.messages.last?.role, .assistant)
        XCTAssertEqual(conversation.messages.last?.text, "Second answer")
        XCTAssertEqual(conversation.messages.last?.status, .sent)
        XCTAssertNil(store.errorMessage(for: conversationID))
    }

    @MainActor
    func testStopSendingKeepsPartialAssistantReplyWithoutErrorBanner() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let store = ChatStore(
            repository: repository,
            aiService: CancellableStreamingAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: store.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await store.applyActivationCode(activationCode, now: now)
        let conversationID = await store.createConversation()
        store.updateDraftText("Stop this answer", for: conversationID)

        let sendTask = Task {
            await store.sendMessage(in: conversationID)
        }

        let didStartSending = await waitUntil {
            store.isSending(conversationID: conversationID)
        }
        XCTAssertTrue(didStartSending)

        let didStreamPartialReply = await waitUntil {
            store.conversation(id: conversationID)?
                .messages
                .last(where: { $0.role == .assistant })?
                .text == "Partial reply"
        }
        XCTAssertTrue(didStreamPartialReply)

        store.stopSending(in: conversationID)
        await sendTask.value

        let conversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertFalse(store.isSending(conversationID: conversationID))
        XCTAssertNil(store.errorMessage(for: conversationID))
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.first?.role, .user)
        XCTAssertEqual(conversation.messages.first?.text, "Stop this answer")
        XCTAssertEqual(conversation.messages.last?.role, .assistant)
        XCTAssertEqual(conversation.messages.last?.text, "Partial reply")
        XCTAssertEqual(conversation.messages.last?.status, .failed)
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return condition()
    }
}

private struct MockTranscriptionService: AITranscriptionService {
    let transcript: String

    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        VoiceTranscriptionResult(
            text: transcript,
            model: configuration.model
        )
    }
}

private struct EchoReplyAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let latestUserText = conversation.messages.last(where: { $0.role == .user })?.cleanedText ?? "missing"

        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("Echo: \(latestUserText)"))
            continuation.finish()
        }
    }
}

private final class FailingThenSuccessTranscriptionService: AITranscriptionService {
    private let failuresBeforeSuccess: Int
    private let transcript: String
    private let lock = NSLock()

    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int, transcript: String) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.transcript = transcript
    }

    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        let attemptNumber = lock.withLock {
            callCount += 1
            return callCount
        }

        if attemptNumber <= failuresBeforeSuccess {
            throw URLError(.networkConnectionLost, userInfo: [
                NSLocalizedDescriptionKey: "temporary transcription failure \(attemptNumber)"
            ])
        }

        return VoiceTranscriptionResult(
            text: transcript,
            model: configuration.model
        )
    }
}

private final class CapturingTranscriptionService: AITranscriptionService {
    private let transcript: String
    private let lock = NSLock()

    private(set) var requestedModels: [String] = []

    init(transcript: String) {
        self.transcript = transcript
    }

    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        lock.withLock {
            requestedModels.append(configuration.model)
        }

        return VoiceTranscriptionResult(
            text: transcript,
            model: configuration.model
        )
    }
}

private final class CapturingAIStreamingService: AIStreamingService {
    private let lock = NSLock()

    private(set) var conversations: [ConversationThread] = []

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        lock.withLock {
            conversations.append(conversation)
        }

        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta("Captured reply"))
            continuation.finish()
        }
    }
}

private final class FailingThenSuccessAIStreamingService: AIStreamingService {
    private let failuresBeforeSuccess: Int
    private let lock = NSLock()

    private(set) var callCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let latestUserText = conversation.messages.last(where: { $0.role == .user })?.cleanedText ?? "missing"
        let attemptNumber: Int = {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }()

        return AsyncThrowingStream { continuation in
            if attemptNumber <= failuresBeforeSuccess {
                continuation.finish(
                    throwing: URLError(.networkConnectionLost, userInfo: [
                        NSLocalizedDescriptionKey: "temporary failure \(attemptNumber)"
                    ])
                )
                return
            }

            continuation.yield(.answerDelta("Echo: \(latestUserText)"))
            continuation.finish()
        }
    }
}

private final class SequentialReplyAIStreamingService: AIStreamingService {
    private let replies: [String]
    private let lock = NSLock()

    private(set) var callCount = 0

    init(replies: [String]) {
        self.replies = replies
    }

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let replyIndex: Int = {
            lock.lock()
            defer { lock.unlock() }
            let index = min(callCount, replies.count - 1)
            callCount += 1
            return index
        }()

        let reply = replies[replyIndex]
        return AsyncThrowingStream { continuation in
            continuation.yield(.answerDelta(reply))
            continuation.finish()
        }
    }
}

private struct CancellableStreamingAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                continuation.yield(.answerDelta("Partial reply"))

                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }
}
