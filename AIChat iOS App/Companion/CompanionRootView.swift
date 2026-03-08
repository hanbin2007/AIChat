#if COMPANION_APP
//
//  CompanionRootView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct CompanionRootView: View {
    @StateObject private var chatStore: ChatStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedConversationID: UUID?

    init() {
        let configuration = AppConfiguration.load()
        let repository = ConversationRepository(configuration: configuration)
        let service = AIServiceFactory.makeService(configuration: configuration)
        let transcriptionService = AIServiceFactory.makeTranscriptionService(configuration: configuration)
        let syncBridge = CompanionSyncBridge()
        _chatStore = StateObject(
            wrappedValue: ChatStore(
                repository: repository,
                aiService: service,
                transcriptionService: transcriptionService,
                configuration: configuration,
                syncBridge: syncBridge
            )
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CompanionConversationListView(
                selectedConversationID: $selectedConversationID,
                onCreateConversation: createConversation
            )
        } detail: {
            if let selectedConversationID {
                CompanionConversationDetailView(conversationID: selectedConversationID)
            } else {
                CompanionEmptySelectionView(
                    isReadOnlyMode: chatStore.isReadOnlyMode,
                    onCreateConversation: createConversation
                )
            }
        }
        .environmentObject(chatStore)
        .task {
            await chatStore.loadConversationsIfNeeded()
            reconcileSelection(with: chatStore.conversations.map(\.id))
        }
        .onChange(of: chatStore.conversations.map(\.id)) { ids in
            reconcileSelection(with: ids)
        }
    }

    private func createConversation() {
        Task {
            let conversationID = await chatStore.createConversation()
            await MainActor.run {
                selectedConversationID = conversationID
            }
        }
    }

    private func reconcileSelection(with ids: [UUID]) {
        guard ids.isEmpty == false else {
            selectedConversationID = nil
            return
        }

        guard let selectedConversationID, ids.contains(selectedConversationID) else {
            self.selectedConversationID = ids.first
            return
        }
    }
}

private struct CompanionEmptySelectionView: View {
    let isReadOnlyMode: Bool
    let onCreateConversation: () -> Void

    var body: some View {
        ZStack {
            AppBackdropView()

            VStack(alignment: .leading, spacing: 20) {
                Text("AIChat")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(
                    isReadOnlyMode ?
                    "当前会话已同步到 iPhone。完成当前设备激活后，你可以在这里直接继续发消息、录音和传图。" :
                    "左侧选择一个会话，或直接新建一条对话，在 iPhone 上继续和手表保持同步。"
                )
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))

                Button(action: onCreateConversation) {
                    Label(isReadOnlyMode ? "查看已同步会话" : "开始新会话", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isReadOnlyMode ? .orange : .cyan)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .padding(24)
        }
    }
}
#endif
