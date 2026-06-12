//
//  AIChat_Watch_AppTests.swift
//  AIChat Watch AppTests
//
//  Created by zhb on 2026/3/7.
//

import Combine
import SwiftUI
import UserNotifications
import XCTest
@testable import AIChat_Watch_App

final class AIChat_Watch_AppTests: XCTestCase {
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
                backendMode: .relay,
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
                backendMode: .relay,
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

    func testContextWindowMergesConsecutiveMessagesFromSameRoleIntoParts() {
        let messages = [
            ChatMessage(role: .user, text: "第一句"),
            ChatMessage(role: .user, text: "第二句"),
            ChatMessage(role: .assistant, text: "回答")
        ]

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .relay,
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
        XCTAssertEqual(contents[0].role, "user")
        XCTAssertEqual(contents[0].parts.compactMap(\.text), ["第一句", "第二句"])
        XCTAssertEqual(contents[1].role, "model")
        XCTAssertEqual(contents[1].parts.compactMap(\.text), ["回答"])
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

    func testAssistantMessageNormalizerExtractsMarkdownDataImageAndDropsRawModelParts() {
        let dataURI = "data:image/png;base64,\(onePixelPNGBase64)"
        let original = ChatMessage(
            role: .assistant,
            text: "Before\n\n![generated](\(dataURI))\n\nAfter",
            modelResponseParts: [
                GeminiPart(
                    text: "Before\n\n![generated](\(dataURI))\n\nAfter",
                    inlineData: nil
                )
            ]
        )

        let normalized = AssistantMessageContentNormalizer.normalized(message: original)

        XCTAssertEqual(normalized.text, "Before\n\nAfter")
        XCTAssertEqual(normalized.attachments.count, 1)
        XCTAssertEqual(normalized.attachments.first?.mimeType, "image/png")
        XCTAssertNil(normalized.modelResponseParts)
        XCTAssertFalse(normalized.text.contains("data:image/"))
    }

    func testAssistantMessageNormalizerExtractsHTMLDataImage() {
        let html = #"<img alt="generated" src="data:image/png;base64,"# + onePixelPNGBase64 + #"" />"#
        let normalized = AssistantMessageContentNormalizer.normalized(
            message: ChatMessage(role: .assistant, text: html)
        )

        XCTAssertEqual(normalized.text, "")
        XCTAssertEqual(normalized.attachments.count, 1)
        XCTAssertEqual(normalized.attachments.first?.mimeType, "image/png")
    }

    func testAssistantMessageNormalizerHidesStreamingPartialDataImageTail() {
        let partialBase64 = String(onePixelPNGBase64.prefix(24))
        let normalized = AssistantMessageContentNormalizer.normalized(
            message: ChatMessage(
                role: .assistant,
                text: "Here it is\n\n![generated](data:image/png;base64,\(partialBase64)",
                status: .streaming
            )
        )

        XCTAssertEqual(normalized.text.trimmingCharacters(in: .whitespacesAndNewlines), "Here it is")
        XCTAssertTrue(normalized.attachments.isEmpty)
        XCTAssertFalse(normalized.text.contains("data:image/"))
    }

    func testAssistantMessageCleanedTextPrefersModelResponsePartsToPreserveMarkdownAcrossSplitParts() {
        let message = ChatMessage(
            role: .assistant,
            text: "**场景\n1：**",
            modelResponseParts: [
                GeminiPart(text: "**场景", inlineData: nil),
                GeminiPart(text: "1：**", inlineData: nil)
            ]
        )

        XCTAssertEqual(message.cleanedText, "**场景1：**")
    }

    func testAssistantMessageCleanedThoughtSummaryPrefersModelResponseParts() {
        let message = ChatMessage(
            role: .assistant,
            text: "Final answer",
            thoughtSummary: "旧的思考摘要",
            modelResponseParts: [
                GeminiPart(text: "推理片段 A", inlineData: nil, thought: true),
                GeminiPart(text: " + B", inlineData: nil, thought: true),
                GeminiPart(text: "Final answer", inlineData: nil)
            ]
        )

        XCTAssertEqual(message.cleanedThoughtSummary, "推理片段 A + B")
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
                backendMode: .relay,
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

    func testMergeGeminiStreamModelResponsePartsKeepsVisibleTextWhenFinalChunkOnlyCarriesThoughtSignature() {
        let merged = mergeGeminiStreamModelResponseParts(
            previousParts: [
                GeminiPartPayload(text: "你可以用 Python 帮我画图。")
            ],
            incomingParts: [
                GeminiPartPayload(text: "", thoughtSignature: "sig-final")
            ]
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.text, "你可以用 Python 帮我画图。")
        XCTAssertEqual(merged.last?.text, "")
        XCTAssertEqual(merged.last?.thoughtSignature, "sig-final")
    }

    func testMergeGeminiStreamModelResponsePartsAccumulatesAllIncomingParts() {
        let firstChunk = [
            GeminiPartPayload(text: "第一段思考", thought: true)
        ]
        let secondChunk = [
            GeminiPartPayload(text: "第二段思考", thought: true),
            GeminiPartPayload(text: "第一段回答")
        ]
        let thirdChunk = [
            GeminiPartPayload(text: "第二段回答"),
            GeminiPartPayload(text: "", thoughtSignature: "sig-final")
        ]

        let mergedAfterFirst = mergeGeminiStreamModelResponseParts(
            previousParts: nil,
            incomingParts: firstChunk
        )
        let mergedAfterSecond = mergeGeminiStreamModelResponseParts(
            previousParts: mergedAfterFirst,
            incomingParts: secondChunk
        )
        let mergedAfterThird = mergeGeminiStreamModelResponseParts(
            previousParts: mergedAfterSecond,
            incomingParts: thirdChunk
        )

        XCTAssertEqual(
            mergedAfterThird,
            [
                GeminiPartPayload(text: "第一段思考", thought: true),
                GeminiPartPayload(text: "第二段思考", thought: true),
                GeminiPartPayload(text: "第一段回答"),
                GeminiPartPayload(text: "第二段回答"),
                GeminiPartPayload(text: "", thoughtSignature: "sig-final")
            ]
        )
    }

    func testMergeGeminiStreamModelResponsePartsReplacesOverlappingSnapshotPrefix() {
        let merged = mergeGeminiStreamModelResponseParts(
            previousParts: [
                GeminiPartPayload(text: "正在推导", thought: true)
            ],
            incomingParts: [
                GeminiPartPayload(text: "正在推导更完整版本", thought: true),
                GeminiPartPayload(text: "最终结论")
            ]
        )

        XCTAssertEqual(
            merged,
            [
                GeminiPartPayload(text: "正在推导更完整版本", thought: true),
                GeminiPartPayload(text: "最终结论")
            ]
        )
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
                backendMode: .relay,
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
        XCTAssertEqual(requestBody.generationConfig.topP, 0.95)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, "high")
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertEqual(requestBody.generationConfig.enableEnhancedCivicAnswers, true)
        XCTAssertNil(requestBody.generationConfig.mediaResolution)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
        XCTAssertEqual(requestBody.safetySettings, GeminiSafetySetting.aiStudioDefaults)
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
                backendMode: .relay,
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
        XCTAssertEqual(requestBody.generationConfig.topP, 0.95)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingLevel, nil)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.thinkingBudget, 8_192)
        XCTAssertEqual(requestBody.generationConfig.thinkingConfig?.includeThoughts, true)
        XCTAssertNil(requestBody.generationConfig.enableEnhancedCivicAnswers)
        XCTAssertNil(requestBody.generationConfig.mediaResolution)
        XCTAssertEqual(requestBody.generationConfig.maxOutputTokens, 65_536)
        XCTAssertEqual(requestBody.safetySettings, GeminiSafetySetting.aiStudioDefaults)
    }

    func testGeminiRequestUsesHighMediaResolutionWhenImageIsAttached() {
        let imageData = Data([0x01, 0x02, 0x03])
        let attachment = ChatImageAttachment(
            kind: .image,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            data: imageData,
            pixelWidth: 10,
            pixelHeight: 10
        )
        let conversation = ConversationThread(
            messages: [
                ChatMessage(role: .user, text: "看这张图", attachments: [attachment])
            ],
            aiConfiguration: ConversationAIConfiguration(model: "gemini-3-flash-preview")
        )

        let client = GeminiAPIClient(
            configuration: AppConfiguration(
                backendMode: .relay,
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

        XCTAssertEqual(requestBody.generationConfig.mediaResolution, "MEDIA_RESOLUTION_HIGH")
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
                backendMode: .relay,
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

    func testPreviewImageReusesDecodedImageForRepeatedAccess() throws {
        let attachment = try makeOnePixelImageAttachment()

        let firstPreview = try XCTUnwrap(attachment.previewImage)
        let secondPreview = try XCTUnwrap(attachment.previewImage)

        XCTAssertTrue(firstPreview === secondPreview)
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
            - 公式：`f(x) = x^2 + 1`
            """,
            count: 40
        ).joined(separator: "\n")

        // Long markdown without math falls back to plain for perf, but
        // expanded mode still returns markdown for full rendering.
        XCTAssertEqual(text.preferredAssistantMessageTextRenderingMode, .plain)
        XCTAssertEqual(
            AssistantMessageTextRenderingDecider.expandedMode(for: text),
            .markdown
        )
    }

    @MainActor
    func testConversationThreadListSummaryCapturesPreviewAndAttachmentFlags() {
        let conversation = ConversationThread(
            title: "Summary",
            messages: [
                ChatMessage(role: .user, text: "First question"),
                ChatMessage(
                    role: .assistant,
                    text: "Attached image only",
                    attachments: [
                        ChatImageAttachment(
                            kind: .image,
                            filename: "photo.jpg",
                            mimeType: "image/jpeg",
                            data: Data([0x01]),
                            pixelWidth: 1,
                            pixelHeight: 1
                        )
                    ]
                ),
                ChatMessage(
                    role: .user,
                    text: "",
                    attachments: [
                        try! ChatAttachment.makeRecordedAudio(
                            from: Data([0x02]),
                            suggestedFilename: "voice.m4a",
                            durationSeconds: 1.2
                        )
                    ]
                )
            ]
        )

        let summary = ConversationThreadListSummary(conversation: conversation)

        XCTAssertEqual(summary.previewText, L10n.tr("conversation.attachment.voice.one"))
        XCTAssertEqual(summary.messageCount, 3)
        XCTAssertTrue(summary.containsAudioAttachments)
        XCTAssertTrue(summary.containsImageAttachments)
    }

    @MainActor
    func testConversationListPublishesOnlyMeaningfulUpdatesDuringStreamingReply() async throws {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000611") ?? UUID()
        let baseDate = Date(timeIntervalSince1970: 1_763_000_000)
        let store = ChatStore.previewStore(
            conversations: [
                ConversationThread(
                    id: conversationID,
                    title: "Streaming Cache Target",
                    createdAt: baseDate,
                    updatedAt: baseDate,
                    isFavorite: false,
                    messages: [
                        ChatMessage(
                            role: .user,
                            text: "Keep the history row stable while the assistant streams.",
                            createdAt: baseDate
                        )
                    ]
                ),
                ConversationThread(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000612") ?? UUID(),
                    title: "Older Thread",
                    createdAt: baseDate.addingTimeInterval(-60),
                    updatedAt: baseDate.addingTimeInterval(-60),
                    isFavorite: false,
                    messages: [
                        ChatMessage(
                            role: .assistant,
                            text: "Older message that should stay below the streaming target.",
                            createdAt: baseDate.addingTimeInterval(-60)
                        )
                    ]
                )
            ],
            aiService: DelayedPreviewAIStreamingService(
                steps: [
                    (60_000_000, .answerDelta("First partial. ")),
                    (60_000_000, .answerDelta("Second partial. ")),
                    (60_000_000, .answerDelta("Final reply.")),
                ]
            ),
            completionFeedbackProvider: NoopCompletionFeedbackProvider()
        )

        var publishedSnapshots: [[WatchConversationListItem]] = []
        let cancellable = store.$conversationListItems
            .dropFirst()
            .sink { publishedSnapshots.append($0) }
        defer { cancellable.cancel() }

        await store.retryLatestReply(in: conversationID)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertLessThanOrEqual(
            publishedSnapshots.count,
            4,
            "Streaming list cache published too many intermediate updates: \(publishedSnapshots.count)"
        )
        XCTAssertEqual(store.conversationListItems.first?.id, conversationID)
        XCTAssertEqual(store.conversationListItems.first?.previewText, "First partial. Second partial. Final reply.")
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
                backendMode: .relay,
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

    func testRelayModeIsConfiguredWithOnlyRelayBaseURL() {
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

        XCTAssertTrue(configuration.isAIConfigured)
        XCTAssertEqual(
            configuration.configurationMessage,
            L10n.tr("configuration.relay.ready")
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
                backendMode: .relay,
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
                backendMode: .relay,
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
                backendMode: .relay,
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
                backendMode: .relay,
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
                backendMode: .relay,
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)

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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        store.updateDraftText("Ping", for: conversationID)

        await store.sendMessage(in: conversationID)

        XCTAssertEqual(feedbackProvider.prepareCallCount, 1)
        XCTAssertEqual(feedbackProvider.notifiedEvents, [.assistantReplyCompleted])
    }

    @MainActor
    func testRecordedAudioRetriesBeforeFailing() async throws {
        let defaultsSuiteName = "AIChatTests.TranscriptionRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults,
            sendRetryDelayNanoseconds: { _ in 0 }
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
            backendMode: .relay,
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
            backendMode: .relay,
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
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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

        // Grant managed relay access so isReadOnlyMode is false and
        // createConversation succeeds.
        await seedManagedRelayAccess(into: store)

        store.updateDefaultConversationModel("gemini-3.1-pro-preview")
        store.updateDefaultConversationThinkingIntensity(.deep)
        store.updateDefaultConversationSystemPrompt("Answer like a release manager.")

        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        let conversation = try XCTUnwrap(store.conversation(id: conversationID))

        XCTAssertEqual(conversation.aiConfiguration?.model, "gemini-3.1-pro-preview")
        XCTAssertEqual(conversation.aiConfiguration?.thinkingIntensity, .deep)
        XCTAssertEqual(conversation.aiConfiguration?.customSystemPrompt, "Answer like a release manager.")
    }

    @MainActor
    func testRecordedAudioUsesSelectedTranscriptionModel() async throws {
        let suiteName = "AIChatTests.TranscriptionSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
            backendMode: .relay,
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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

        let activationRepository = ActivationRepository(configuration: configuration, rootURL: repositoryRootURL)
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
        await seedManagedRelayAccess(into: store)

        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
    func testReadOnlyStoreCanDeleteConversation() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repositoryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-ReadOnlyDelete-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuiteName = "AIChatTests-ReadOnlyDelete-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let repository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let conversationID = UUID()

        try await repository.save(
            ConversationThread(
                id: conversationID,
                title: "Read Only Delete",
                messages: [
                    ChatMessage(role: .assistant, text: "Delete should stay available in read-only mode.")
                ]
            )
        )

        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: ActivationRepository(configuration: configuration, rootURL: repositoryRootURL),
            defaults: defaults
        )

        await store.loadConversationsIfNeeded()
        XCTAssertTrue(store.isReadOnlyMode)
        XCTAssertEqual(store.conversations.map(\.id), [conversationID])

        await store.deleteConversation(id: conversationID)

        XCTAssertTrue(store.conversations.isEmpty)
        let loadedTombstones = try await repository.loadDeletedConversationTombstones()
        XCTAssertNotNil(loadedTombstones[conversationID])
    }

    @MainActor
    func testRemoteDeletionTombstoneRemovesStaleLocalConversation() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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

        let activationRepository = ActivationRepository(configuration: configuration, rootURL: watchRepositoryRootURL)
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
        await seedManagedRelayAccess(into: watchStore)

        let conversationIDOrNil = await watchStore.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        let sharedConversationCandidate = watchStore.conversation(id: conversationID)
        let sharedConversation = try XCTUnwrap(sharedConversationCandidate)

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
    func testRemoteDeletionTombstoneRemovesLocallyModifiedConversation() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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

        let activationRepository = ActivationRepository(configuration: configuration, rootURL: watchRepositoryRootURL)
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
        await seedManagedRelayAccess(into: watchStore)

        let conversationIDOrNil = await watchStore.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        let sharedConversationCandidate = watchStore.conversation(id: conversationID)
        let sharedConversation = try XCTUnwrap(sharedConversationCandidate)

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

        var locallyModifiedConversation = sharedConversation
        locallyModifiedConversation.title = "Locally Modified"
        locallyModifiedConversation.updatedAt = deletedAt.addingTimeInterval(60)
        await iphoneStore.mergeRemoteConversationSnapshot([locallyModifiedConversation])
        XCTAssertEqual(iphoneStore.conversation(id: conversationID)?.title, "Locally Modified")

        await iphoneStore.mergeRemoteDeletedConversationTombstones([
            CompanionDeletedConversationTombstone(id: conversationID, deletedAt: deletedAt)
        ])

        XCTAssertTrue(iphoneStore.conversations.isEmpty)
        let iphoneTombstones = try await iphoneRepository.loadDeletedConversationTombstones()
        XCTAssertEqual(iphoneTombstones[conversationID], deletedAt)
    }

    @MainActor
    func testRemoteConversationSnapshotHydratesImportedAttachmentBlob() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repositoryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatTests-HydrateRemote-\(UUID().uuidString)", isDirectory: true)
        let repository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        let attachmentData = try XCTUnwrap(Data(base64Encoded: onePixelPNGBase64))
        let attachment = try ChatAttachment.makeModelGeneratedImage(
            from: attachmentData,
            mimeType: "image/png",
            suggestedFilename: "remote-sync"
        )
        let blobFilename = "remote-sync-\(attachment.id.uuidString).png"
        try FileManager.default.createDirectory(at: repositoryRootURL, withIntermediateDirectories: true)
        let temporaryFileURL = repositoryRootURL.appendingPathComponent("incoming-image.png", isDirectory: false)
        try attachment.data.write(to: temporaryFileURL, options: [.atomic])
        _ = try await repository.importAttachmentBlob(from: temporaryFileURL, as: blobFilename)

        let conversationID = UUID()
        let messageID = UUID()
        let remoteConversation = ConversationThread(
            id: conversationID,
            title: "Remote Snapshot Attachment",
            messages: [
                ChatMessage(
                    id: messageID,
                    role: .assistant,
                    text: "Hydrated image",
                    attachments: [
                        ChatAttachment(
                            id: attachment.id,
                            kind: .image,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            data: Data(),
                            blobFilename: blobFilename,
                            pixelWidth: attachment.pixelWidth,
                            pixelHeight: attachment.pixelHeight
                        )
                    ]
                )
            ]
        )

        await store.mergeRemoteConversationSnapshot([remoteConversation])

        let hydratedAttachment = try XCTUnwrap(
            store.conversation(id: conversationID)?.messages.first?.attachments.first
        )
        XCTAssertEqual(hydratedAttachment.blobFilename, blobFilename)
        XCTAssertEqual(hydratedAttachment.data, attachment.data)
    }

    @MainActor
    func testDeletedConversationDoesNotReturnWhenBackgroundRefreshFinishesLate() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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

        let activationRepository = ActivationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let rawDeviceIdentifier = "TEST-DEVICE-\(UUID().uuidString)"
        let deviceToken = OfflineActivation.deviceToken(for: rawDeviceIdentifier)
        let deviceIdentity = WatchDeviceIdentity(
            rawIdentifier: rawDeviceIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )
        let memoryMaintenanceService = BlockingMemoryMaintenanceService()
        let repository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            memoryMaintenanceService: memoryMaintenanceService,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: activationRepository,
            deviceIdentity: deviceIdentity,
            defaults: defaults
        )
        await seedManagedRelayAccess(into: store)

        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        store.updateDraftText("Remember that I prefer concise release notes.", for: conversationID)

        let sendTask = Task {
            await store.sendMessage(in: conversationID)
        }

        let didStartRefresh = await memoryMaintenanceService.waitUntilRefreshStarts()
        XCTAssertTrue(didStartRefresh, "Memory refresh should start before the conversation is deleted.")

        await store.deleteConversation(id: conversationID)
        XCTAssertTrue(store.conversations.isEmpty)

        memoryMaintenanceService.resume()
        await sendTask.value

        XCTAssertTrue(store.conversations.isEmpty)

        let restartedRepository = ConversationRepository(configuration: configuration, rootURL: repositoryRootURL)
        let restartedStore = ChatStore(
            repository: restartedRepository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            memoryMaintenanceService: HeuristicMemoryMaintenanceService(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: activationRepository,
            deviceIdentity: deviceIdentity,
            defaults: defaults
        )
        await restartedStore.loadConversationsIfNeeded()

        XCTAssertTrue(restartedStore.conversations.isEmpty)
        let loadedTombstones = try await restartedRepository.loadDeletedConversationTombstones()
        XCTAssertNotNil(loadedTombstones[conversationID])
    }

    @MainActor
    func testGlobalPinnedMemoryIsInjectedOnlyWhenConversationOptsIn() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)

        let sourceConversationIDOrNil = await store.createConversation()
        let sourceConversationID = try XCTUnwrap(sourceConversationIDOrNil)
        store.updateDraftText("记住我是高二理科生。", for: sourceConversationID)
        await store.sendMessage(in: sourceConversationID)

        let sourceConversation = try XCTUnwrap(store.conversation(id: sourceConversationID))
        let sourceMessageID = try XCTUnwrap(sourceConversation.messages.first(where: { $0.role == .user })?.id)
        await store.pinMessage(id: sourceMessageID, from: sourceConversationID, scope: .global)

        let localOnlyConversationIDOrNil = await store.createConversation()
        let localOnlyConversationID = try XCTUnwrap(localOnlyConversationIDOrNil)
        store.updateDraftText("我们先随便聊聊。", for: localOnlyConversationID)
        await store.sendMessage(in: localOnlyConversationID)
        XCTAssertTrue(aiService.conversations.last?.pinnedMemories.isEmpty == true)

        let globalMemoryConversationIDOrNil = await store.createConversation()
        let globalMemoryConversationID = try XCTUnwrap(globalMemoryConversationIDOrNil)
        await store.updateUsesGlobalPinnedMemory(true, for: globalMemoryConversationID)
        store.updateDraftText("继续聊今天的计划。", for: globalMemoryConversationID)
        await store.sendMessage(in: globalMemoryConversationID)

        let injectedPinnedMemories = aiService.conversations.last?.pinnedMemories ?? []
        XCTAssertEqual(injectedPinnedMemories.count, 1)
        XCTAssertEqual(injectedPinnedMemories.first?.scope, .global)
        XCTAssertEqual(injectedPinnedMemories.first?.text, "记住我是高二理科生。")
    }

    @MainActor
    func testConversationToolTogglesUpdateImmediatelyAndPersistLatestState() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-ToolToggles-\(UUID().uuidString)", isDirectory: true)
        )
        let store = ChatStore(
            repository: repository,
            aiService: CapturingAIStreamingService(),
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)

        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        store.setGoogleSearchEnabled(true, for: conversationID)
        store.setCodeExecutionEnabled(true, for: conversationID)

        let inMemoryConfiguration = store.aiConfiguration(for: conversationID)
        XCTAssertTrue(inMemoryConfiguration.usesGoogleSearch)
        XCTAssertTrue(inMemoryConfiguration.usesCodeExecution)

        var persistedConfiguration: ConversationAIConfiguration?
        for _ in 0..<20 {
            let persistedConversation = try await repository.loadConversations()
                .first(where: { $0.id == conversationID })
            persistedConfiguration = persistedConversation?.aiConfiguration

            if persistedConfiguration?.usesGoogleSearch == true &&
                persistedConfiguration?.usesCodeExecution == true {
                break
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(persistedConfiguration?.usesGoogleSearch, true)
        XCTAssertEqual(persistedConfiguration?.usesCodeExecution, true)
    }

    @MainActor
    func testSendMessageRetriesBeforeReportingFailure() async throws {
        let suiteName = "AIChatTests.SendRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            defaults: defaults,
            sendRetryDelayNanoseconds: { _ in 0 }
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
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
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )
        await seedManagedRelayAccess(into: store)
        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
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
    func testSendMessagePersistsStreamingReplyProgressAndReleasesReplyPersistenceController() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "test",
            geminiModel: "gemini-3.1-pro-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "http://127.0.0.1:8787"),
            relayBearerToken: "test-token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatTests-\(UUID().uuidString)", isDirectory: true)
        )
        let aiService = CancellableStreamingAIStreamingService()
        let replyPersistenceController = MockReplyPersistenceController()
        let store = ChatStore(
            repository: repository,
            aiService: aiService,
            transcriptionService: nil,
            completionFeedbackProvider: NoopCompletionFeedbackProvider(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            replyPersistenceController: replyPersistenceController
        )
        await seedManagedRelayAccess(into: store)

        let conversationIDOrNil = await store.createConversation()
        let conversationID = try XCTUnwrap(conversationIDOrNil)
        store.updateDraftText("Persist this answer", for: conversationID)

        let sendTask = Task {
            await store.sendMessage(in: conversationID)
        }

        let didStartSending = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            store.isSending(conversationID: conversationID)
        }
        XCTAssertTrue(didStartSending)

        let didStreamPartialReply = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            store.conversation(id: conversationID)?
                .messages
                .last(where: { $0.role == .assistant })?
                .text == "Partial reply"
        }
        XCTAssertTrue(didStreamPartialReply)

        let persistedConversation = try await waitForPersistedConversation(
            in: repository,
            conversationID: conversationID
        ) { conversation in
            conversation.messages.last?.role == .assistant &&
            conversation.messages.last?.text == "Partial reply" &&
            conversation.messages.last?.status == .streaming
        }

        let partialConversation = try XCTUnwrap(persistedConversation)
        XCTAssertEqual(partialConversation.messages.last?.text, "Partial reply")
        XCTAssertEqual(partialConversation.messages.last?.status, .streaming)
        XCTAssertEqual(replyPersistenceController.begunTokens.count, 1)
        XCTAssertTrue(replyPersistenceController.endedTokens.isEmpty)

        store.stopSending(in: conversationID)
        await sendTask.value

        XCTAssertEqual(replyPersistenceController.begunTokens, replyPersistenceController.endedTokens)

        let finalConversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(finalConversation.messages.last?.status, .failed)
        XCTAssertEqual(finalConversation.messages.last?.text, "Partial reply")
    }

    @MainActor
    func testLoadConversationsRecoversPersistedStreamingReplyAsFailed() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
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
        let conversationID = UUID()
        try await repository.save(
            ConversationThread(
                id: conversationID,
                messages: [
                    ChatMessage(role: .user, text: "What happened?"),
                    ChatMessage(
                        role: .assistant,
                        text: "Partial reply",
                        status: .streaming
                    )
                ]
            )
        )

        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            replyPersistenceController: NoopReplyPersistenceController.shared
        )

        await store.loadConversationsIfNeeded()

        let loadedConversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(loadedConversation.messages.last?.text, "Partial reply")
        XCTAssertEqual(loadedConversation.messages.last?.status, .failed)

        let persistedConversations = try await repository.loadConversations()
        let persistedConversation = try XCTUnwrap(
            persistedConversations.first(where: { $0.id == conversationID })
        )
        XCTAssertEqual(persistedConversation.messages.last?.status, .failed)
    }

    @MainActor
    func testLoadConversationsDropsEmptyRecoveredStreamingReply() async throws {
        let configuration = AppConfiguration(
            backendMode: .relay,
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
        let conversationID = UUID()
        try await repository.save(
            ConversationThread(
                id: conversationID,
                messages: [
                    ChatMessage(role: .user, text: "Still there?"),
                    ChatMessage(
                        role: .assistant,
                        text: "",
                        status: .streaming
                    )
                ]
            )
        )

        let store = ChatStore(
            repository: repository,
            aiService: EchoReplyAIStreamingService(),
            transcriptionService: nil,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            replyPersistenceController: NoopReplyPersistenceController.shared
        )

        await store.loadConversationsIfNeeded()

        let loadedConversation = try XCTUnwrap(store.conversation(id: conversationID))
        XCTAssertEqual(loadedConversation.messages.count, 1)
        XCTAssertEqual(loadedConversation.messages.first?.role, .user)

        let persistedConversations = try await repository.loadConversations()
        let persistedConversation = try XCTUnwrap(
            persistedConversations.first(where: { $0.id == conversationID })
        )
        XCTAssertEqual(persistedConversation.messages.count, 1)
        XCTAssertEqual(persistedConversation.messages.first?.role, .user)
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

    @MainActor
    private func waitForPersistedConversation(
        in repository: ConversationRepository,
        conversationID: UUID,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping (ConversationThread) -> Bool
    ) async throws -> ConversationThread? {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let conversation = try await repository
                .loadConversations()
                .first(where: { $0.id == conversationID && condition($0) }) {
                return conversation
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return try await repository
            .loadConversations()
            .first(where: { $0.id == conversationID && condition($0) })
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

@MainActor
private final class MockReplyPersistenceController: ReplyPersistenceControlling {
    private(set) var begunTokens: [UUID] = []
    private(set) var endedTokens: [UUID] = []

    func beginStreamingReplyPersistence() -> UUID {
        let token = UUID()
        begunTokens.append(token)
        return token
    }

    func endStreamingReplyPersistence(_ token: UUID) {
        endedTokens.append(token)
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

private nonisolated struct DelayedPreviewAIStreamingService: AIStreamingService {
    let steps: [(delayNanoseconds: UInt64, event: AIStreamEvent)]

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamTask = Task {
                do {
                    for step in steps {
                        try await Task.sleep(nanoseconds: step.delayNanoseconds)
                        continuation.yield(step.event)
                    }

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

private final class BlockingMemoryMaintenanceService: AIMemoryMaintenanceService {
    private let lock = NSLock()
    private var didStartRefresh = false
    private var continuation: CheckedContinuation<Void, Never>?

    func refreshArtifacts(for conversation: ConversationThread) async -> ConversationMemoryArtifacts {
        lock.withLock {
            didStartRefresh = true
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        return ConversationMemoryArtifacts(
            focusState: ConversationFocusState(
                kind: .task,
                title: "Release Notes",
                focusNote: "Keep the summary concise.",
                sourceMessageIDs: conversation.messages.map(\.id)
            ),
            memoryItems: [
                ConversationMemoryItem(
                    text: "User prefers concise release notes.",
                    keywords: ["concise", "release", "notes"],
                    sourceMessageIDs: conversation.messages.map(\.id)
                )
            ],
            archiveSegments: []
        )
    }

    func waitUntilRefreshStarts(timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if lock.withLock({ didStartRefresh }) {
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return lock.withLock({ didStartRefresh })
    }

    func resume() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
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
