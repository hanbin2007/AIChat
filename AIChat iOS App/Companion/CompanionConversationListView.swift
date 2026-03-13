#if COMPANION_APP
//
//  CompanionConversationListView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct CompanionConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore

    @Binding var selectedConversationID: UUID?
    let onCreateConversation: () -> Void

    @State private var isShowingActivationCenter = false
    @State private var isShowingGlobalSettings = false
    @State private var isShowingFavorites = false
    @State private var isShowingPromptLibrary = false

    var body: some View {
        ZStack {
            AppBackdropView()

            List(selection: $selectedConversationID) {
                Section {
                    ActivationStatusCard(
                        title: chatStore.activationStatusTitle,
                        message: chatStore.activationStatusMessage,
                        iconName: chatStore.isReadOnlyMode ? "lock.fill" : "checkmark.seal.fill",
                        accentColor: chatStore.isReadOnlyMode ? .orange : .green,
                        actionTitle: chatStore.isReadOnlyMode ? "立即激活" : "管理授权"
                    ) {
                        isShowingActivationCenter = true
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                if chatStore.configuration.isAIConfigured == false {
                    Section {
                        ConfigurationBannerView(message: chatStore.configuration.configurationMessage)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    ConfigurationBannerView(
                        iconName: "network",
                        title: chatStore.configuration.backendSummary,
                        message: "\(chatStore.storageDescription) • \(chatStore.syncStatusDescription)"
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                if let startupError = chatStore.startupError {
                    Section {
                        ConfigurationBannerView(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Storage Error",
                            message: startupError
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }

                Section("会话") {
                    if chatStore.conversations.isEmpty {
                        CompanionConversationEmptyState(
                            isReadOnlyMode: chatStore.isReadOnlyMode,
                            onCreateConversation: onCreateConversation,
                            onOpenActivation: { isShowingActivationCenter = true }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(chatStore.conversations) { conversation in
                            CompanionConversationRow(
                                conversation: conversation,
                                aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                            )
                            .tag(conversation.id)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    Task {
                                        await chatStore.setConversationFavorite(
                                            conversation.isFavorite == false,
                                            for: conversation.id
                                        )
                                    }
                                } label: {
                                    Label(
                                        conversation.isFavorite ? L10n.tr("favorites.remove") : L10n.tr("favorites.add"),
                                        systemImage: conversation.isFavorite ? "star.slash" : "star"
                                    )
                                }
                                .tint(conversation.isFavorite ? .orange : .yellow)

                                if chatStore.isReadOnlyMode == false {
                                    Button(role: .destructive) {
                                        Task {
                                            await chatStore.deleteConversation(id: conversation.id)
                                        }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AIChat")
        .sheet(isPresented: $isShowingActivationCenter) {
            CompanionActivationCenterView()
        }
        .sheet(isPresented: $isShowingGlobalSettings) {
            CompanionGlobalSettingsView()
        }
        .sheet(isPresented: $isShowingFavorites) {
            CompanionFavoritesView(selectedConversationID: $selectedConversationID)
        }
        .sheet(isPresented: $isShowingPromptLibrary) {
            CompanionPromptLibraryView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    isShowingActivationCenter = true
                } label: {
                    Image(systemName: chatStore.isReadOnlyMode ? "key.fill" : "checkmark.seal")
                }
                .accessibilityLabel(chatStore.isReadOnlyMode ? "激活当前设备" : "管理授权")

                Button {
                    isShowingGlobalSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("全局设置")

                Button {
                    isShowingFavorites = true
                } label: {
                    Image(systemName: "star")
                }
                .accessibilityLabel(L10n.tr("favorites.title"))

                Button {
                    isShowingPromptLibrary = true
                } label: {
                    Image(systemName: "text.book.closed")
                }
                .accessibilityLabel(L10n.tr("prompt_preset.library.title"))
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onCreateConversation) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建会话")
                .disabled(chatStore.isReadOnlyMode)
            }
        }
    }
}

private struct CompanionConversationEmptyState: View {
    let isReadOnlyMode: Bool
    let onCreateConversation: () -> Void
    let onOpenActivation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isReadOnlyMode ? "同步已就绪" : "从 iPhone 开始继续聊")
                .font(.headline)
                .foregroundStyle(.white)

            Text(
                isReadOnlyMode ?
                "你现在可以在 iPhone 上查看同步过来的历史消息。完成当前设备激活后，就能直接继续发送。" :
                "新建一条会话后，iPhone 和手表会共享同一套聊天记录、模型设置、图片与录音上下文。"
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.78))

            Button {
                if isReadOnlyMode {
                    onOpenActivation()
                } else {
                    onCreateConversation()
                }
            } label: {
                Label(isReadOnlyMode ? "去激活" : "新建会话", systemImage: isReadOnlyMode ? "key.fill" : "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isReadOnlyMode ? .orange : .cyan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.vertical, 6)
    }
}

struct CompanionConversationRow: View {
    let conversation: ConversationThread
    let aiConfiguration: ConversationAIConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(conversation.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if conversation.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Spacer(minLength: 0)

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }

            Text(conversation.previewText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CompanionMetaChip(
                        title: L10n.format("conversation.count.ios", conversation.messageCount),
                        iconName: "bubble.left.and.bubble.right.fill"
                    )

                    if conversation.containsAudioAttachments {
                        CompanionMetaChip(title: "语音", iconName: "waveform")
                    }

                    if conversation.containsImageAttachments {
                        CompanionMetaChip(title: "图片", iconName: "photo")
                    }

                    CompanionMetaChip(title: AIModelCatalog.shortLabel(for: aiConfiguration.model), iconName: "cpu")
                    CompanionMetaChip(title: aiConfiguration.thinkingIntensity.shortLabel, iconName: "brain.head.profile")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.vertical, 4)
    }
}

private struct CompanionMetaChip: View {
    let title: String
    let iconName: String

    var body: some View {
        Label(title, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.cyan.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}
#endif
