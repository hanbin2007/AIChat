//
//  AIChatRegistrationApp.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

@main
struct AIChatRegistrationApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if COMPANION_APP
    @StateObject private var chatStore: ChatStore
    private let initialConversationID: UUID?
    private let uiTestLaunchDestination: CompanionUITestLaunchDestination?

    init() {
        #if DEBUG
        if let bootstrap = CompanionUITestBootstrap.makeIfNeeded() {
            _chatStore = StateObject(wrappedValue: bootstrap.store)
            initialConversationID = bootstrap.initialConversationID
            uiTestLaunchDestination = bootstrap.launchDestination
            return
        }
        #endif

        let configuration = AppConfiguration.load()
        let repository = ConversationRepository(configuration: configuration)
        let service = AIServiceFactory.makeService(configuration: configuration)
        let transcriptionService = AIServiceFactory.makeTranscriptionService(configuration: configuration)
        let memoryMaintenanceService = AIServiceFactory.makeMemoryMaintenanceService(configuration: configuration)
        let syncBridge = CompanionSyncBridge()
        let cloudSyncService = ICloudConversationSyncService(configuration: configuration)
        _chatStore = StateObject(
            wrappedValue: ChatStore(
                repository: repository,
                aiService: service,
                transcriptionService: transcriptionService,
                memoryMaintenanceService: memoryMaintenanceService,
                configuration: configuration,
                syncBridge: syncBridge,
                cloudSyncService: cloudSyncService
            )
        )
        initialConversationID = nil
        uiTestLaunchDestination = nil
    }
    #endif

    var body: some Scene {
        WindowGroup {
            #if COMPANION_APP
            Group {
                if case let .conversationDetail(conversationID)? = uiTestLaunchDestination {
                    NavigationStack {
                        CompanionConversationDetailView(conversationID: conversationID)
                    }
                } else {
                    CompanionRootView(initialSelectedConversationID: initialConversationID)
                }
            }
            .environmentObject(chatStore)
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }

                Task {
                    await chatStore.refreshRemoteSyncState()
                }
            }
            .preferredColorScheme(.dark)
            #else
            OfflineActivationKeygenView()
                .preferredColorScheme(.dark)
            #endif
        }
    }
}

#if COMPANION_APP
private enum CompanionUITestLaunchDestination: Equatable {
    case root
    case conversationDetail(UUID)
}
#endif

#if DEBUG && COMPANION_APP
private struct CompanionUITestBootstrap {
    let store: ChatStore
    let initialConversationID: UUID?
    let launchDestination: CompanionUITestLaunchDestination

    static func makeIfNeeded() -> CompanionUITestBootstrap? {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["AIChat_UI_TEST_SCENARIO"] else {
            return nil
        }

        switch scenario {
        case "companion_heavy_markdown":
            let conversation = heavyMarkdownConversation()
            return CompanionUITestBootstrap(
                store: MainActor.assumeIsolated {
                    ChatStore.previewStore(conversations: [conversation])
                },
                initialConversationID: conversation.id,
                launchDestination: .conversationDetail(conversation.id)
            )
        case "companion_image_attachment":
            let conversation = imageAttachmentConversation()
            return CompanionUITestBootstrap(
                store: MainActor.assumeIsolated {
                    ChatStore.previewStore(conversations: [conversation])
                },
                initialConversationID: conversation.id,
                launchDestination: .conversationDetail(conversation.id)
            )
        case "companion_delete_read_only":
            let conversation = readOnlyDeleteConversation()
            return CompanionUITestBootstrap(
                store: MainActor.assumeIsolated {
                    ChatStore.previewStore(
                        conversations: [conversation],
                        activationState: nil
                    )
                },
                initialConversationID: conversation.id,
                launchDestination: .conversationDetail(conversation.id)
            )
        case "companion_streaming_fade_in":
            // Visual demo for issue #22: opens a conversation and triggers a
            // slow assistant stream so the per-character trailing fade in
            // `StreamingFadeInTextView` is visible to a screenshot.
            let conversation = streamingFadeInConversation()
            let store = MainActor.assumeIsolated {
                ChatStore.previewStore(
                    conversations: [conversation],
                    aiService: CompanionStreamingFadeInService()
                )
            }

            Task { @MainActor in
                // Small grace so the detail view has actually mounted before
                // the pacer starts emitting deltas. Otherwise the very first
                // tokens are dropped on the floor and the bubble starts
                // mid-message instead of from the empty "Thinking" state.
                try? await Task.sleep(nanoseconds: 600_000_000)
                await store.retryLatestReply(in: conversation.id)
            }

            return CompanionUITestBootstrap(
                store: store,
                initialConversationID: conversation.id,
                launchDestination: .conversationDetail(conversation.id)
            )
        case "companion_compact_delete_pops":
            // Regression scenario for issue #32. Two conversations; the UI
            // test deletes the open one and asserts the empty-selection
            // placeholder takes over instead of auto-jumping into the other.
            let pair = compactDeletePair()
            return CompanionUITestBootstrap(
                store: MainActor.assumeIsolated {
                    ChatStore.previewStore(conversations: pair)
                },
                initialConversationID: pair[0].id,
                launchDestination: .conversationDetail(pair[0].id)
            )
        default:
            return nil
        }
    }

    private static func heavyMarkdownConversation() -> ConversationThread {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000401") ?? UUID()
        let repeatedBlock = Array(
            repeating: """
            ## 推导步骤
            - 先整理条件并拆成小结论。
            - 关键公式：$$\\sum_{i=1}^{36} \\frac{a_i + b_i + c_i}{\\sqrt{x_i^2 + y_i^2 + z_i^2}} = \\prod_{k=1}^{12} (\\alpha_k + \\beta_k)$$
            - 最终范围：**$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**
            """,
            count: 12
        ).joined(separator: "\n\n")

        // The companion detail view force-expands whichever message is the
        // latest in the conversation. The heavy-markdown collapse / expand
        // button only renders for non-latest messages, so we need a trailing
        // user message after the assistant block — otherwise the expand
        // button never appears and the UI test asserts on a phantom element.
        return ConversationThread(
            id: conversationID,
            title: "Companion Heavy Markdown",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000402") ?? UUID(),
                    role: .assistant,
                    text: repeatedBlock
                ),
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000403") ?? UUID(),
                    role: .user,
                    text: "好的，先这样。"
                )
            ]
        )
    }

    private static func imageAttachmentConversation() -> ConversationThread {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000411") ?? UUID()
        let imageData = Data(base64Encoded: onePixelPNGBase64) ?? Data()
        let attachment = ChatAttachment(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000413") ?? UUID(),
            kind: .image,
            filename: "ui-test-image.png",
            mimeType: "image/png",
            data: imageData,
            pixelWidth: 1,
            pixelHeight: 1
        )

        return ConversationThread(
            id: conversationID,
            title: "Companion Image Attachment",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000412") ?? UUID(),
                    role: .assistant,
                    text: "这里有一张生成图片，确认 iPhone 侧可以直接显示并点开查看。",
                    attachments: [attachment]
                )
            ]
        )
    }

    private static func readOnlyDeleteConversation() -> ConversationThread {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000421") ?? UUID()

        return ConversationThread(
            id: conversationID,
            title: "Companion Read Only Delete",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000422") ?? UUID(),
                    role: .assistant,
                    text: "这是一条来自已配对手表的同步会话，未激活的 iPhone 也应该能删除它。"
                )
            ]
        )
    }

    private static func streamingFadeInConversation() -> ConversationThread {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000431") ?? UUID()
        // The store needs a previously-streamed assistant reply that
        // `retryLatestReply` can resurrect. The user message becomes the
        // prompt that the slow streaming service will answer.
        return ConversationThread(
            id: conversationID,
            title: "Companion Streaming Fade In",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000432") ?? UUID(),
                    role: .user,
                    text: "演示一下流式渐入动画。"
                ),
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000433") ?? UUID(),
                    role: .assistant,
                    text: "（占位回复，UI 测试启动后会被重发的流式结果替换。）",
                    status: .failed
                )
            ]
        )
    }

    private static func compactDeletePair() -> [ConversationThread] {
        let openID = UUID(uuidString: "00000000-0000-0000-0000-000000000441") ?? UUID()
        let neighborID = UUID(uuidString: "00000000-0000-0000-0000-000000000442") ?? UUID()
        let open = ConversationThread(
            id: openID,
            title: "Companion Compact Delete Open",
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "这是当前打开的会话，删除它后不应该自动跳进另一条。"
                )
            ]
        )
        let neighbor = ConversationThread(
            id: neighborID,
            title: "Companion Compact Delete Neighbor",
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "邻居会话；删除上一条后应保持在列表里，由用户自己决定下一步。"
                )
            ]
        )
        return [open, neighbor]
    }

    private static let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW2QAAAAASUVORK5CYII="
}

/// Slow-paced streaming service used by the `companion_streaming_fade_in`
/// UI test scenario. Emits short Chinese segments at ~5Hz so the
/// per-character trailing fade-in (issue #22) is large enough to capture in
/// a single screenshot. Total wall-clock is ~6s which fits well inside the
/// UI test's 10s wait windows.
private struct CompanionStreamingFadeInService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                continuation.yield(
                    .thoughtDelta("演示：流式回复的渐入动画。")
                )

                let chunks: [String] = [
                    "智能", "手表", "上的", "聊天", "界面", "应该",
                    "保持", "干净、", "克制。", "新的",
                    "渐入", "字符", "动画", "让", "回复", "看起来",
                    "像被", "一只", "手", "轻轻", "揭开", "毯子",
                    "推出", "来。"
                ]

                for chunk in chunks {
                    guard Task.isCancelled == false else {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: 220_000_000)
                    continuation.yield(.answerDelta(chunk))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
#endif
