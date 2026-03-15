//
//  AIChat_Watch_AppTests.swift
//  AIChat Watch AppTests
//
//  Created by zhb on 2026/3/7.
//

import SwiftUI
import UserNotifications
import XCTest
@testable import AIChat_Watch_App

final class AIChat_Watch_AppTests: XCTestCase {
    private let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW2QAAAAASUVORK5CYII="

    func testSuggestedTitleUsesCollapsedWhitespaceAndTruncates() {
        let input = "  Build   a production ready Apple Watch assistant with photo upload   "
        let title = ConversationThread.suggestedTitle(from: input)

        XCTAssertEqual(title, "Build a production ready A...")
    }

    func testAIChatDeepLinkParsesActivationImport() {
        let url = URL(string: "aichat://activation/import?code=abcd-1234-efgh")!

        XCTAssertEqual(
            AIChatDeepLink(url),
            .activationImport("ABCD-1234-EFGH")
        )
    }

    func testAIChatDeepLinkParsesNewConversation() {
        let url = URL(string: "aichat://conversation/new")!

        XCTAssertEqual(AIChatDeepLink(url), .newConversation)
    }

    func testCompletionFeedbackForegroundPresentationOptionsEnableSound() {
        let options = CompletionFeedbackEvent.foregroundPresentationOptions(
            forNotificationIdentifier: CompletionFeedbackEvent.transcriptionCompleted.notificationIdentifier
        )

        XCTAssertTrue(options.contains(.sound))
    }

    func testCompletionFeedbackForegroundPresentationOptionsIgnoreUnknownNotifications() {
        let options = CompletionFeedbackEvent.foregroundPresentationOptions(
            forNotificationIdentifier: "some-other-notification"
        )

        XCTAssertEqual(options, [])
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
        XCTAssertEqual(contents[0].parts.last?.inlineData?.mimeType, "audio/aac")
        XCTAssertEqual(contents[0].parts.last?.inlineData?.data, audioData.base64EncodedString())
    }

    func testRecordedAudioDefaultsToAacMimeTypeAndExtension() throws {
        let attachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x10, 0x20, 0x30]),
            suggestedFilename: "voice.wav",
            durationSeconds: 3.2
        )

        XCTAssertEqual(attachment.mimeType, "audio/aac")
        XCTAssertTrue(attachment.filename.hasSuffix(".aac"))
    }

    func testRecordedAudioCanPreserveWavFallbackMimeTypeAndExtension() throws {
        let attachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x10, 0x20, 0x30]),
            suggestedFilename: "voice.wav",
            durationSeconds: 3.2,
            mimeType: "audio/wav"
        )

        XCTAssertEqual(attachment.mimeType, "audio/wav")
        XCTAssertTrue(attachment.filename.hasSuffix(".wav"))
    }

    func testContextWindowReusesStoredAssistantModelParts() {
        let storedParts = [
            GeminiPart(
                text: "Hidden reasoning summary",
                inlineData: nil,
                thought: true,
                thoughtSignature: "sig-1"
            ),
            GeminiPart(
                text: "Visible answer",
                inlineData: nil,
                thought: false,
                thoughtSignature: "sig-2"
            )
        ]
        let messages = [
            ChatMessage(role: .user, text: "Question"),
            ChatMessage(
                role: .assistant,
                text: "Visible answer",
                thoughtSummary: "Hidden reasoning summary",
                modelResponseParts: storedParts
            )
        ]

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

        XCTAssertEqual(contents.count, 2)
        XCTAssertEqual(contents[1].role, "model")
        XCTAssertEqual(contents[1].parts, storedParts)
        XCTAssertEqual(contents[1].parts.first?.thoughtSignature, "sig-1")
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

        XCTAssertEqual(requestBody.systemInstruction?.parts.first?.text, AIContextAssembler.conciseSystemPrompt)
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

    func testPromptPresetLibraryIncludesBuiltInsByDefault() {
        let presets = PromptPreset.resolvedLibrary(from: [])

        XCTAssertTrue(
            presets.contains(where: {
                $0.id == PromptPreset.builtInConversationID &&
                $0.kind == .conversation &&
                $0.isBuiltIn
            })
        )
        XCTAssertTrue(
            presets.contains(where: {
                $0.id == PromptPreset.builtInTranscriptionID &&
                $0.kind == .transcription &&
                $0.isBuiltIn
            })
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

    func testGeminiRequestIncludesEnabledTools() {
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "Compare the latest SwiftData changes and verify with a script.")],
            aiConfiguration: ConversationAIConfiguration(
                model: "gemini-2.5-flash",
                usesGoogleSearch: true,
                usesCodeExecution: true
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

        XCTAssertEqual(requestBody.tools?.count, 2)
        XCTAssertNotNil(requestBody.tools?.first?.googleSearch)
        XCTAssertNotNil(requestBody.tools?.last?.codeExecution)
    }

    func testExtractImageAttachmentsReturnsGeneratedImages() throws {
        let responseData = try XCTUnwrap(
            """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {
                        "inlineData": {
                          "mimeType": "image/png",
                          "data": "\(onePixelPNGBase64)"
                        }
                      }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """.data(using: .utf8)
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: responseData)
        var emittedKeys: Set<String> = []

        let attachments = extractImageAttachments(
            from: responseEnvelope,
            emittedKeys: &emittedKeys
        )

        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.mimeType, "image/png")
        XCTAssertEqual(attachments.first?.kind, .image)
        XCTAssertEqual(attachments.first?.data.base64EncodedString(), onePixelPNGBase64)
    }

    func testAssistantMessageContentNormalizerExtractsMarkdownDataImagesIntoAttachments() {
        let markdown = """
        这是一幅图像。

        ![](data:image/png;base64,\(onePixelPNGBase64))

        附加说明。
        """

        let extraction = AssistantMessageContentNormalizer.extractEmbeddedImages(from: markdown)

        XCTAssertTrue(extraction.didChange)
        XCTAssertFalse(extraction.text.contains("data:image"))
        XCTAssertTrue(extraction.text.contains("这是一幅图像。"))
        XCTAssertTrue(extraction.text.contains("附加说明。"))
        XCTAssertEqual(extraction.attachments.count, 1)
        XCTAssertEqual(extraction.attachments.first?.mimeType, "image/png")
        XCTAssertNotNil(extraction.attachments.first?.previewImage)
    }

    func testAssistantMessageContentNormalizerNormalizesConversationHistory() {
        let conversation = ConversationThread(
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "![](data:image/png;base64,\(onePixelPNGBase64))"
                )
            ]
        )

        let normalization = AssistantMessageContentNormalizer.normalized(conversation: conversation)

        XCTAssertTrue(normalization.didChange)
        XCTAssertEqual(normalization.conversation.messages.count, 1)
        XCTAssertEqual(normalization.conversation.messages[0].text, "")
        XCTAssertEqual(normalization.conversation.messages[0].attachments.count, 1)
        XCTAssertEqual(normalization.conversation.messages[0].attachments.first?.mimeType, "image/png")
    }

    func testAssistantMessageRenderingModeUsesPlainTextForSimpleReplies() {
        let text = "这是一个普通回复，没有列表、代码块或数学公式。"

        XCTAssertEqual(text.preferredAssistantMessageTextRenderingMode, .plain)
    }

    func testAssistantMessageRenderingModeUsesMarkdownForCompactStructuredReplies() {
        let text = """
        ## 总结
        - 第一项
        - 第二项
        """

        XCTAssertEqual(text.preferredAssistantMessageTextRenderingMode, .markdown)
    }

    func testAssistantMessageRenderingModeFallsBackToPlainForLongMarkdownReplies() {
        let text = Array(repeating: "- 长列表项内容", count: 80).joined(separator: "\n")

        XCTAssertEqual(text.preferredAssistantMessageTextRenderingMode, .plain)
    }

    func testAssistantMessageExpandedRenderingModeKeepsMarkdownForLongStructuredReplies() {
        let text = Array(
            repeating: """
            ## 推导
            - 列出条件
            - 公式：$$x^2 + y^2 = z^2$$
            """,
            count: 40
        ).joined(separator: "\n")

        XCTAssertEqual(text.preferredAssistantMessageTextRenderingMode, .plain)
        XCTAssertEqual(
            AssistantMessageTextRenderingDecider.expandedMode(for: text),
            .markdown
        )
    }

    @MainActor
    func testConversationDetailInitialRenderPerformanceForHeavyCollapsedHistory() async throws {
        let conversation = ConversationThread(
            title: "Heavy Markdown",
            messages: makeHeavyMarkdownMessages(count: 8)
        )
        let store = try await makeLoadedStore(conversations: [conversation])
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: conversation.messages,
                budget: 10
            ),
            1
        )

        measure(metrics: [XCTClockMetric()], options: options) {
            let start = CFAbsoluteTimeGetCurrent()
            let snapshot = renderConversationDetailSnapshot(
                store: store,
                conversationID: conversation.id
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            XCTAssertNotNil(snapshot)
            XCTAssertLessThan(
                elapsed,
                0.25,
                "Heavy conversation initial render regressed to \(elapsed)s"
            )
        }
    }

    @MainActor
    func testConversationDetailInitialRenderPerformanceForHeavyLatexHistory() async throws {
        let conversation = ConversationThread(
            title: "Heavy LaTeX",
            messages: makeHeavyLatexMessages(count: 6)
        )
        let store = try await makeLoadedStore(conversations: [conversation])
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let start = CFAbsoluteTimeGetCurrent()
            let snapshot = renderConversationDetailSnapshot(
                store: store,
                conversationID: conversation.id
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - start

            XCTAssertNotNil(snapshot)
            XCTAssertLessThan(
                elapsed,
                0.25,
                "Heavy LaTeX conversation initial render regressed to \(elapsed)s"
            )
        }
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

    func testMergedGeminiTextPreservesFormulaSplitAcrossParts() {
        let parts = [
            GeminiPart(text: "因此 $b$ 的取值范围为：\n**$b \\in (0", inlineData: nil),
            GeminiPart(text: ", \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**", inlineData: nil),
            GeminiPart(text: "ignored", inlineData: nil, thought: true)
        ]

        XCTAssertEqual(
            mergedGeminiText(from: parts, includeThoughts: false),
            "因此 $b$ 的取值范围为：\n**$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**"
        )
        XCTAssertEqual(mergedGeminiText(from: parts, includeThoughts: true), "ignored")
    }

    func testNormalizedDeltaPreservesWhitespaceAndSplitMathBoundaries() {
        var currentText = ""

        XCTAssertEqual(
            normalizedDelta(chunkText: "**$b \\in (0", currentText: &currentText),
            "**$b \\in (0"
        )
        XCTAssertEqual(
            normalizedDelta(
                chunkText: "**$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**",
                currentText: &currentText
            ),
            ", \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**"
        )

        currentText = "Answer"
        XCTAssertEqual(normalizedDelta(chunkText: "Answer ", currentText: &currentText), " ")
        XCTAssertEqual(currentText, "Answer ")
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
        XCTAssertEqual(request.systemPrompt, AIContextAssembler.conciseSystemPrompt)
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

        XCTAssertEqual(request.messages.count, 3)
        XCTAssertEqual(request.messages[1].role, "assistant")
        XCTAssertEqual(request.messages[1].modelResponseParts, storedParts)
    }

    func testMemoryExtractionIgnoresHiddenAssistantModelPartsWithoutVisibleText() async {
        let extractor = CapturingMemoryExtractionClient(
            response: ConversationMemoryExtractionResponse()
        )
        let service = ModelBackedMemoryMaintenanceService(
            extractor: extractor,
            defaultModel: "gemini-3-flash-preview"
        )
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .user, text: "Original question"),
                ChatMessage(
                    role: .assistant,
                    text: "",
                    modelResponseParts: [
                        GeminiPart(
                            text: nil,
                            inlineData: nil,
                            thought: true,
                            thoughtSignature: "sig-hidden"
                        )
                    ]
                ),
                ChatMessage(role: .user, text: "Follow-up request")
            ],
            aiConfiguration: ConversationAIConfiguration(model: "gemini-3-flash-preview")
        )

        _ = await service.refreshArtifacts(for: conversation)
        let request = await extractor.capturedRequest

        XCTAssertEqual(
            request?.recentMessages.map(\.text),
            ["Original question", "Follow-up request"]
        )
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
            L10n.tr("configuration.relay.missing_bearer")
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
        XCTAssertEqual(request.audio.mimeType, "audio/aac")
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
        XCTAssertEqual(request.contents[0].parts.last?.inlineData?.mimeType, "audio/aac")
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
    func testRecordedAudioTranscriptionTriggersCompletionFeedback() async throws {
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
        let feedbackProvider = MockTranscriptionCompletionFeedbackProvider()
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: MockTranscriptionService(transcript: "Transcript ready"),
            completionFeedbackProvider: feedbackProvider,
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

        XCTAssertEqual(feedbackProvider.prepareCallCount, 1)
        XCTAssertEqual(feedbackProvider.notifiedEvents, [.transcriptionCompleted])
    }

    @MainActor
    func testRecordedAudioTranscriptionAppendsToExistingDraft() async throws {
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
            transcriptionService: MockTranscriptionService(transcript: "Add the second instruction"),
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
        store.updateDraftText("Keep the first instruction", for: conversationID)
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x04, 0x05, 0x06]),
            suggestedFilename: "voice.wav",
            durationSeconds: 2.4
        )

        await store.sendRecordedAudio(audioAttachment, in: conversationID)

        XCTAssertEqual(
            store.draftText(for: conversationID),
            "Keep the first instruction Add the second instruction"
        )
        XCTAssertTrue(store.conversation(id: conversationID)?.messages.isEmpty == true)
    }

    @MainActor
    func testRecordedAudioCanBeSentDirectlyWithoutClearingDraft() async throws {
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
        let conversationID = await store.createConversation()
        store.updateDraftText("Keep this draft", for: conversationID)
        let audioAttachment = try ChatAttachment.makeRecordedAudio(
            from: Data([0x11, 0x22, 0x33]),
            suggestedFilename: "voice.wav",
            durationSeconds: 4.1
        )

        await store.sendRecordedAudioDirectly(audioAttachment, in: conversationID)

        let conversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.first?.role, .user)
        XCTAssertEqual(conversation.messages.first?.text, "")
        XCTAssertEqual(conversation.messages.first?.attachments.count, 1)
        XCTAssertTrue(conversation.messages.first?.attachments.first?.isAudio == true)
        XCTAssertEqual(conversation.messages.last?.text, "Captured reply")
        XCTAssertEqual(store.draftText(for: conversationID), "Keep this draft")

        let capturedConversation = try XCTUnwrap(aiService.conversations.last)
        XCTAssertEqual(capturedConversation.messages.last?.role, .user)
        XCTAssertEqual(capturedConversation.messages.last?.attachments.count, 1)
        XCTAssertTrue(capturedConversation.messages.last?.attachments.first?.isAudio == true)
    }

    @MainActor
    func testRestoreLatestUserMessageToDraftUsesMostRecentUserText() async throws {
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

        store.updateDraftText("First prompt", for: conversationID)
        await store.sendMessage(in: conversationID)
        store.updateDraftText("Second prompt", for: conversationID)
        await store.sendMessage(in: conversationID)

        XCTAssertEqual(store.latestReusableUserMessageText(for: conversationID), "Second prompt")
        XCTAssertTrue(store.restoreLatestUserMessageToDraft(for: conversationID))
        XCTAssertEqual(store.draftText(for: conversationID), "Second prompt")
    }

    @MainActor
    func testSendMessageTriggersAssistantReplyCompletionFeedback() async throws {
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
        let feedbackProvider = MockTranscriptionCompletionFeedbackProvider()
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: feedbackProvider,
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
        store.updateDraftText("Ping", for: conversationID)

        await store.sendMessage(in: conversationID)

        XCTAssertEqual(feedbackProvider.prepareCallCount, 1)
        XCTAssertEqual(feedbackProvider.notifiedEvents, [.assistantReplyCompleted])
    }

    @MainActor
    func testRecordedAudioRetriesBeforeFailing() async throws {
        let now = Date(timeIntervalSince1970: 1_762_399_980)
        let defaultsSuiteName = "AIChatTests.TranscriptionRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
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
    func testDeletedConversationDoesNotReturnFromOlderRemoteSnapshotAfterRestart() async throws {
        let now = Date(timeIntervalSince1970: 1_762_400_200)
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
        let repositoryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuiteName = "AIChatTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let activationRepository = ActivationRepository(defaults: defaults)
        let rawDeviceIdentifier = "TEST-DEVICE-\(UUID().uuidString)"
        let deviceToken = OfflineActivation.deviceToken(for: rawDeviceIdentifier)
        let deviceIdentity = WatchDeviceIdentity(
            rawIdentifier: rawDeviceIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )
        let repository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: activationRepository,
            deviceIdentity: deviceIdentity,
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
        await store.renameConversation(id: conversationID, title: "Delete Me")
        let deletedConversation = try XCTUnwrap(store.conversation(id: conversationID))

        await store.deleteConversation(id: conversationID)
        XCTAssertTrue(store.conversations.isEmpty)

        let restartedRepository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let restartedStore = ChatStore(
            repository: restartedRepository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: activationRepository,
            deviceIdentity: deviceIdentity,
            defaults: defaults
        )

        await restartedStore.loadConversationsIfNeeded()
        XCTAssertTrue(restartedStore.conversations.isEmpty)

        await restartedStore.mergeRemoteConversationSnapshot([deletedConversation])

        XCTAssertTrue(restartedStore.conversations.isEmpty)
        let loadedTombstones = try await restartedRepository.loadDeletedConversationTombstones()
        XCTAssertNotNil(loadedTombstones[conversationID])
    }

    @MainActor
    func testRemoteDeletionTombstoneRemovesStaleLocalConversation() async throws {
        let now = Date(timeIntervalSince1970: 1_762_400_260)
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
        let watchRepositoryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-Watch-\(UUID().uuidString)", isDirectory: true)
        let iphoneRepositoryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-iPhone-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuiteName = "AIChatTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let activationRepository = ActivationRepository(defaults: defaults)
        let rawDeviceIdentifier = "TEST-DEVICE-\(UUID().uuidString)"
        let deviceToken = OfflineActivation.deviceToken(for: rawDeviceIdentifier)
        let deviceIdentity = WatchDeviceIdentity(
            rawIdentifier: rawDeviceIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )

        let watchRepository = ConversationRepository(configuration: configuration, rootURL: watchRepositoryRootURL)
        let watchStore = ChatStore(
            repository: watchRepository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: activationRepository,
            deviceIdentity: deviceIdentity,
            defaults: defaults
        )
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: watchStore.activationRequestCode(now: now),
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )
        try await watchStore.applyActivationCode(activationCode, now: now)

        let conversationID = await watchStore.createConversation()
        let sharedConversation = try XCTUnwrap(watchStore.conversation(id: conversationID))

        let iphoneRepository = ConversationRepository(configuration: configuration, rootURL: iphoneRepositoryRootURL)
        let iphoneStore = ChatStore(
            repository: iphoneRepository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await iphoneStore.mergeRemoteConversationSnapshot([sharedConversation])
        XCTAssertEqual(iphoneStore.conversations.map(\.id), [conversationID])

        await watchStore.deleteConversation(id: conversationID)
        let watchTombstones = try await watchRepository.loadDeletedConversationTombstones()
        let deletedAt = try XCTUnwrap(watchTombstones[conversationID])

        let restartedIPhoneRepository = ConversationRepository(configuration: configuration, rootURL: iphoneRepositoryRootURL)
        let restartedIPhoneStore = ChatStore(
            repository: restartedIPhoneRepository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await restartedIPhoneStore.loadConversationsIfNeeded()
        XCTAssertEqual(restartedIPhoneStore.conversations.map(\.id), [conversationID])

        await restartedIPhoneStore.mergeRemoteDeletedConversationTombstones([
            CompanionDeletedConversationTombstone(id: conversationID, deletedAt: deletedAt)
        ])

        XCTAssertTrue(restartedIPhoneStore.conversations.isEmpty)
        let iphoneTombstones = try await restartedIPhoneRepository.loadDeletedConversationTombstones()
        XCTAssertEqual(iphoneTombstones[conversationID], deletedAt)
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

    func testConversationRecencySortPrefersNewestUpdatedAtThenCreatedAt() {
        let older = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "older",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let newer = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "newer",
            createdAt: Date(timeIntervalSince1970: 150),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let tiedUpdateNewerCreate = ConversationThread(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "tie",
            createdAt: Date(timeIntervalSince1970: 180),
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let sorted = [older, newer, tiedUpdateNewerCreate]
            .sorted(by: ConversationThread.sortsByMostRecentFirst)

        XCTAssertEqual(sorted.map(\.title), ["tie", "newer", "older"])
    }

    func testDraftTextComposerAppendsChineseTranscriptWithPunctuationAwareSeparator() {
        let merged = DraftTextComposer.appended(
            existing: "帮我写一封邮件给张三",
            addition: "内容是明天下午三点开会。"
        )

        XCTAssertEqual(merged, "帮我写一封邮件给张三，内容是明天下午三点开会。")
    }

    func testDraftTextComposerKeepsEnglishContinuationInline() {
        let merged = DraftTextComposer.appended(
            existing: "Summarize the meeting",
            addition: "and call out the blockers."
        )

        XCTAssertEqual(merged, "Summarize the meeting and call out the blockers.")
    }

    func testConversationHistoryRenderBudgetDefersSmallHeavyConversation() {
        let messages = makeMessages(
            count: 8,
            text: String(repeating: "Large content block ", count: 280)
        )

        XCTAssertTrue(
            ConversationHistoryRenderBudget.shouldDeferInitialRendering(
                in: messages,
                threshold: 48
            )
        )
        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 10
            ),
            1
        )
    }

    func testConversationHistoryRenderBudgetKeepsSmallLightConversationEager() {
        let messages = makeMessages(
            count: 8,
            text: "Short reply"
        )

        XCTAssertFalse(
            ConversationHistoryRenderBudget.shouldDeferInitialRendering(
                in: messages,
                threshold: 48
            )
        )
        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 10
            ),
            messages.count
        )
    }

    func testConversationHistoryRenderBudgetAlwaysKeepsNewestMessageVisible() {
        let messages = makeMessages(
            count: 1,
            text: String(repeating: "Very long answer ", count: 400)
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: 1
            ),
            1
        )
    }

    func testConversationHistoryRenderBudgetKeepsLoadMoreAnchorAtLastHiddenMessage() {
        let messages = makeMessages(
            count: 5,
            text: "Short reply"
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.lastHiddenMessageID(
                in: messages,
                budget: 2
            ),
            messages[2].id
        )
    }

    func testConversationHistoryRenderBudgetLoadMoreAlwaysRevealsAnotherMessage() {
        let messages = [
            ChatMessage(role: .user, text: "Newest question"),
            ChatMessage(
                role: .assistant,
                text: Array(
                    repeating: """
                    ## 公式
                    $$\\int_0^1 x^4 dx = \\frac{1}{5}$$
                    """,
                    count: 120
                ).joined(separator: "\n")
            ),
            ChatMessage(role: .user, text: "Latest follow-up")
        ]

        let currentBudget = 1
        let nextBudget = ConversationHistoryRenderBudget.budgetForLoadingOlderMessages(
            in: messages,
            currentBudget: currentBudget,
            preferredIncrement: 1
        )

        XCTAssertEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: currentBudget
            ),
            1
        )
        XCTAssertGreaterThanOrEqual(
            ConversationHistoryRenderBudget.visibleMessageCount(
                in: messages,
                budget: nextBudget
            ),
            2
        )
    }

    private func makeMessages(count: Int, text: String) -> [ChatMessage] {
        (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: text
            )
        }
    }

    @MainActor
    private func makeLoadedStore(
        conversations: [ConversationThread]
    ) async throws -> ChatStore {
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
                .appendingPathComponent("AIChatPerf-\(UUID().uuidString)", isDirectory: true)
        )

        for conversation in conversations {
            try await repository.save(conversation)
        }

        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await store.loadConversationsIfNeeded()
        return store
    }

    @MainActor
    private func renderConversationDetailSnapshot(
        store: ChatStore,
        conversationID: UUID
    ) -> CGImage? {
        let width: CGFloat = 184
        let height: CGFloat = 224
        let content = ConversationDetailView(conversationID: conversationID)
            .environmentObject(store)
            .frame(width: width, height: height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }

    private func makeHeavyMarkdownMessages(count: Int) -> [ChatMessage] {
        let heavyMarkdown = Array(
            repeating: """
            ## 推导步骤
            - 先整理条件 `value`
            - 再计算公式 $$\\int_0^1 x^2 dx = \\frac{1}{3}$$

            ```swift
            let answer = 42
            print(answer)
            ```

            这一段用于模拟真实的大段 markdown 与 LaTeX 回复内容。
            """,
            count: 36
        ).joined(separator: "\n\n")

        return (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: index.isMultiple(of: 2) ? "继续第 \(index + 1) 步" : heavyMarkdown
            )
        }
    }

    private func makeHeavyLatexMessages(count: Int) -> [ChatMessage] {
        let heavyLatex = Array(
            repeating: """
            ## 推导
            令 $a_n = \\frac{1}{n^2 + 1}$，并比较下式：

            $$
            f(x) = \\sum_{k=1}^{18} \\frac{x^k}{k!}
            $$

            \\[
            \\int_0^1 \\frac{1}{1 + x^2} dx = \\frac{\\pi}{4}
            \\]

            再验证 $\\alpha^2 + \\beta^2 = \\gamma^2$ 的近似边界。
            """,
            count: 8
        ).joined(separator: "\n\n")

        return (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: index.isMultiple(of: 2) ? "继续公式第 \(index + 1) 步" : heavyLatex
            )
        }
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

@MainActor
private final class MockTranscriptionCompletionFeedbackProvider: CompletionFeedbackProviding {
    private(set) var prepareCallCount = 0
    private(set) var notifiedEvents: [CompletionFeedbackEvent] = []

    func prepareForPossibleBackgroundFeedback() async {
        prepareCallCount += 1
    }

    func notifyCompletion(of event: CompletionFeedbackEvent) async {
        notifiedEvents.append(event)
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

private actor CapturingMemoryExtractionClient: AIMemoryExtractionClient {
    private let response: ConversationMemoryExtractionResponse
    private(set) var capturedRequest: ConversationMemoryExtractionRequest?

    init(response: ConversationMemoryExtractionResponse) {
        self.response = response
    }

    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse {
        capturedRequest = request
        return response
    }
}
