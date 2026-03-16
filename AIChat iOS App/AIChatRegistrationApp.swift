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
            #else
            OfflineActivationKeygenView()
            #endif
        }
    }
}

#if DEBUG && COMPANION_APP
private enum CompanionUITestLaunchDestination: Equatable {
    case root
    case conversationDetail(UUID)
}

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

        return ConversationThread(
            id: conversationID,
            title: "Companion Heavy Markdown",
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000402") ?? UUID(),
                    role: .assistant,
                    text: repeatedBlock
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

    private static let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aW2QAAAAASUVORK5CYII="
}
#endif
