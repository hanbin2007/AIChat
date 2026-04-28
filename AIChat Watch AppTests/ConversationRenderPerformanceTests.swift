//
//  ConversationRenderPerformanceTests.swift
//  AIChat Watch AppTests
//
//  SwiftUI render-time performance tests for ConversationDetailView and
//  ConversationListView. Skipped by default — see `PerformanceTestCase`
//  for the rationale and how to enable.
//
//  Each test uses `measure(metrics:)` so XCTest's per-machine baselines
//  apply. The previous hardcoded `XCTAssertLessThan(elapsed, 0.35)`-style
//  gates were removed because they were producing false negatives under
//  Xcode Cloud simulator load (we observed 8.77s outliers on a 0.35s gate).
//

import Combine
import SwiftUI
import XCTest
@testable import AIChat_Watch_App

final class ConversationRenderPerformanceTests: PerformanceTestCase {
    @MainActor
    private static var retainedConversationListPerformanceStores: [ChatStore] = []

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
            2
        )

        measure(metrics: [XCTClockMetric()], options: options) {
            let snapshot = renderConversationDetailSnapshot(
                store: store,
                conversationID: conversation.id
            )
            XCTAssertNotNil(snapshot)
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
            let snapshot = renderConversationDetailSnapshot(
                store: store,
                conversationID: conversation.id
            )
            XCTAssertNotNil(snapshot)
        }
    }

    @MainActor
    func testConversationListInitialRenderPerformanceForLargeHistory() async throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let snapshot = autoreleasepool { () -> CGImage? in
                let store = ChatStore.previewStore(
                    conversations: makeHistoryListConversations(count: 180),
                    completionFeedbackProvider: NoopCompletionFeedbackProvider()
                )
                Self.retainedConversationListPerformanceStores.append(store)
                return renderConversationListSnapshot(store: store)
            }
            XCTAssertNotNil(snapshot)
        }
    }

    @MainActor
    func testConversationListContinuationRenderPerformance() async throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric()], options: options) {
            let snapshot = autoreleasepool { () -> CGImage? in
                let store = ChatStore.previewStore(
                    conversations: makeHistoryListConversations(count: 180),
                    completionFeedbackProvider: NoopCompletionFeedbackProvider()
                )
                Self.retainedConversationListPerformanceStores.append(store)
                return renderConversationListSnapshot(
                    store: store,
                    initialVisibleConversationLimit: 12
                )
            }
            XCTAssertNotNil(snapshot)
        }
    }

    // MARK: - Helpers

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
            aiService: PerformanceNoopAIStreamingService(),
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

    @MainActor
    private func renderConversationListSnapshot(
        store: ChatStore,
        initialVisibleConversationLimit: Int = 0
    ) -> CGImage? {
        let width: CGFloat = 184
        let height: CGFloat = 224
        let content = ConversationListView(
            navigationPath: .constant([]),
            initialVisibleConversationLimit: initialVisibleConversationLimit
        )
            .environmentObject(store)
            .frame(width: width, height: height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
    }

    private func makeHistoryListConversations(count: Int) -> [ConversationThread] {
        let seededDate = Date(timeIntervalSince1970: 1_762_401_000)

        return (0..<count).map { index in
            let createdAt = seededDate.addingTimeInterval(Double(index * 90))
            let title = "History Thread \(index + 1)"
            return ConversationThread(
                id: UUID(),
                title: title,
                createdAt: createdAt,
                updatedAt: createdAt.addingTimeInterval(30),
                isFavorite: index.isMultiple(of: 11),
                messages: [
                    ChatMessage(
                        role: .assistant,
                        text: """
                        \(title)
                        This seeded history row includes enough text to keep watch list cells realistic during render testing.
                        """,
                        createdAt: createdAt
                    )
                ]
            )
        }
        .sorted(by: ConversationThread.sortsByMostRecentFirst)
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
}

private struct PerformanceNoopAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
