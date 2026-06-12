//
//  PromptAssemblyTests.swift
//  AIChat Watch AppTests
//
//  Tests for `AIContextAssembler` (system-instruction assembly given a
//  conversation focus state, memory, and archive segments) and the prompt
//  preset library defaults.
//

import XCTest
@testable import AIChat_Watch_App

final class PromptAssemblyTests: XCTestCase {
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
            configuration: makeGeminiRequestTestConfiguration(geminiModel: "gemini-3.1-pro-preview")
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
        XCTAssertEqual(assembled.systemInstructionParts?.count, 1)
        XCTAssertEqual(assembled.systemInstructionParts?.first?.text, AIContextAssembler.conciseSystemPrompt)
    }

    func testContextAssemblerIncludesTeachingArtifactsInSystemInstructionParts() {
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
        let instructionText = assembled.systemInstructionParts?.compactMap(\.text).joined(separator: "\n\n")

        XCTAssertEqual(assembled.mode, .teaching)
        XCTAssertTrue(instructionText?.contains("Current focus:") == true)
        XCTAssertTrue(instructionText?.contains("Pinned memory:") == true)
        XCTAssertTrue(instructionText?.contains("Relevant conversation memory:") == true)
        XCTAssertTrue(instructionText?.contains("Archived context:") == true)
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
            configuration: makeGeminiRequestTestConfiguration(geminiModel: "gemini-3-flash-preview")
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
}
