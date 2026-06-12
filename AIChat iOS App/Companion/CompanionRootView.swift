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
    @Environment(\.colorScheme) private var colorScheme
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
                    hasSyncedConversations: chatStore.conversations.isEmpty == false,
                    onPrimaryAction: handleEmptySelectionPrimaryAction
                )
            }
        }
        .background(alignment: .bottom) {
            if shouldExtendBottomSurface {
                Rectangle()
                    .fill(DS.Surface.elevatedStrongFill(for: colorScheme))
                    .frame(height: bottomSurfaceHeight)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(DS.Surface.elevatedStroke(for: colorScheme))
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
        .onChange(of: chatStore.conversations.map(\.id)) { _, ids in
            reconcileSelection(with: ids)
        }
        .onChange(of: selectedConversationID) { _, conversationID in
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

    private func handleEmptySelectionPrimaryAction() {
        guard chatStore.isReadOnlyMode else {
            createConversation()
            return
        }

        if let conversationID = chatStore.conversations.first?.id {
            selectedConversationID = conversationID
        } else {
            isShowingActivationCenter = true
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
    @Environment(\.colorScheme) private var colorScheme

    let isReadOnlyMode: Bool
    let hasSyncedConversations: Bool
    let onPrimaryAction: () -> Void

    var body: some View {
        ZStack {
            AppBackdropView()

            VStack(alignment: .leading, spacing: 20) {
                Text("AIChat")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Text.primary(for: colorScheme))

                Text(
                    isReadOnlyMode ?
                    readOnlyMessage :
                    "左侧选择一个会话，或直接新建一条对话，在 iPhone 上继续和手表保持同步。"
                )
                .font(.body)
                .foregroundStyle(DS.Text.secondary(for: colorScheme))

                Button(action: onPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionIconName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isReadOnlyMode ? .orange : .cyan)
            }
            .padding(28)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(DS.Surface.elevatedFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
                    )
            )
            .padding(24)
        }
        .accessibilityIdentifier("companion.empty-selection")
    }

    private var readOnlyMessage: String {
        if hasSyncedConversations {
            return "当前会话已同步到 iPhone。选择已有同步会话查看历史；完成当前设备激活后即可继续发消息、录音和传图。"
        }

        return "当前设备尚未激活。完成激活后，你可以在这里继续发消息、录音和传图。"
    }

    private var primaryActionTitle: String {
        if isReadOnlyMode {
            return hasSyncedConversations ? "查看已同步会话" : "激活当前设备"
        }

        return "开始新会话"
    }

    private var primaryActionIconName: String {
        if isReadOnlyMode {
            return hasSyncedConversations ? "bubble.left.and.bubble.right.fill" : "key.fill"
        }

        return "square.and.pencil"
    }
}
#endif
