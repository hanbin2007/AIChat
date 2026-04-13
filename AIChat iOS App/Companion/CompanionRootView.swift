#if COMPANION_APP
//
//  CompanionRootView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct CompanionBottomSurfaceHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct CompanionRootView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedConversationID: UUID?
    @State private var bottomSurfaceHeight: CGFloat = 0
    @State private var importedActivationCode = ""
    @State private var isShowingActivationCenter = false

    init(initialSelectedConversationID: UUID? = nil) {
        _selectedConversationID = State(initialValue: initialSelectedConversationID)
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
        .background(alignment: .bottom) {
            if shouldExtendBottomSurface {
                Rectangle()
                    .fill(Color.black.opacity(0.78))
                    .frame(height: bottomSurfaceHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $isShowingActivationCenter) {
            CompanionActivationCenterView(
                prefilledActivationCode: importedActivationCode,
                autoSendToWatch: true
            )
            .id(importedActivationCode)
            .environmentObject(chatStore)
        }
        .onPreferenceChange(CompanionBottomSurfaceHeightKey.self) { height in
            bottomSurfaceHeight = height
        }
        .task {
            await chatStore.loadConversationsIfNeeded()
            reconcileSelection(with: chatStore.conversations.map(\.id))
        }
        .onOpenURL { url in
            guard let deepLink = AIChatDeepLink(url) else {
                return
            }

            handleDeepLink(deepLink)
        }
        .onChange(of: chatStore.conversations.map(\.id)) { ids in
            reconcileSelection(with: ids)
        }
        .onChange(of: selectedConversationID) { conversationID in
            if conversationID == nil {
                bottomSurfaceHeight = 0
            }
        }
    }

    private var shouldExtendBottomSurface: Bool {
        horizontalSizeClass == .regular &&
        selectedConversationID != nil &&
        bottomSurfaceHeight > 0
    }

    private func createConversation() {
        Task {
            if let conversationID = await chatStore.createConversation() {
                await MainActor.run {
                    selectedConversationID = conversationID
                }
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

    private func handleDeepLink(_ deepLink: AIChatDeepLink) {
        switch deepLink {
        case let .activationImport(activationCode):
            importedActivationCode = activationCode
            isShowingActivationCenter = true
        case .newConversation:
            guard chatStore.isReadOnlyMode == false else {
                return
            }

            createConversation()
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
        .accessibilityIdentifier("companion.empty-selection")
    }
}
#endif
