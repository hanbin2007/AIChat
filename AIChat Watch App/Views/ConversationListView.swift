//
//  ConversationListView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var navigationPath: [UUID]
    @State private var isShowingActivationCenter = false

    var body: some View {
        ZStack {
            AppBackdropView()

            List {
                ActivationStatusCard(
                    title: chatStore.activationStatusTitle,
                    message: chatStore.activationStatusMessage,
                    iconName: chatStore.isReadOnlyMode ? "lock.fill" : "checkmark.seal.fill",
                    accentColor: chatStore.isReadOnlyMode ? .orange : .green,
                    actionTitle: chatStore.isReadOnlyMode ? "立即激活" : "管理授权"
                ) {
                    isShowingActivationCenter = true
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                if chatStore.configuration.isAIConfigured == false {
                    ConfigurationBannerView(message: chatStore.configuration.configurationMessage)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                ConfigurationBannerView(
                    iconName: "network",
                    title: chatStore.configuration.backendSummary,
                    message: "\(chatStore.storageDescription) • \(chatStore.syncStatusDescription)"
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                if let startupError = chatStore.startupError {
                    ConfigurationBannerView(
                        iconName: "exclamationmark.triangle.fill",
                        title: "Storage Error",
                        message: startupError
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                if chatStore.conversations.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(chatStore.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRowView(
                                conversation: conversation,
                                aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                            )
                            .equatable()
                        }
                        .accessibilityIdentifier("conversation.row.\(conversation.id.uuidString)")
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            favoriteSwipeAction(for: conversation)
                            deleteSwipeAction(for: conversation)
                        }
                    }
                }
            }
            .accessibilityIdentifier("conversation.list")
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $isShowingActivationCenter) {
            ActivationCenterView()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built for Watch")
                .font(.headline)

            Text(
                chatStore.isReadOnlyMode ?
                "你现在可以查看历史消息。完成手表离线激活后，才能开始新会话并发送消息。" :
                "Context-aware Gemini chat, voice prompts, photo prompts, streaming replies, relay-ready networking, and sync scaffolding for a paired iPhone."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                if chatStore.isReadOnlyMode {
                    isShowingActivationCenter = true
                } else {
                    Task {
                        let newConversationID = await chatStore.createConversation()
                        navigationPath = [newConversationID]
                    }
                }
            } label: {
                Label(
                    chatStore.isReadOnlyMode ? "Activate Watch" : "Start Chat",
                    systemImage: chatStore.isReadOnlyMode ? "key.fill" : "sparkles"
                )
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("conversation.empty.primary")
            .buttonStyle(.borderedProminent)
            .tint(chatStore.isReadOnlyMode ? .orange : .cyan)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversation.empty-state")
    }

    @ViewBuilder
    private func favoriteSwipeAction(for conversation: ConversationThread) -> some View {
        Button {
            Task {
                await chatStore.setConversationFavorite(conversation.isFavorite == false, for: conversation.id)
            }
        } label: {
            Label(
                conversation.isFavorite ? L10n.tr("favorites.remove") : L10n.tr("favorites.add"),
                systemImage: conversation.isFavorite ? "star.slash" : "star"
            )
        }
        .tint(conversation.isFavorite ? .orange : .yellow)
    }

    @ViewBuilder
    private func deleteSwipeAction(for conversation: ConversationThread) -> some View {
        Button(role: .destructive) {
            Task {
                await chatStore.deleteConversation(id: conversation.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("conversation.delete.\(conversation.id.uuidString)")
    }
}
#endif

struct ConversationRowView: View, Equatable {
    let conversation: ConversationThread
    let aiConfiguration: ConversationAIConfiguration

    static func == (lhs: ConversationRowView, rhs: ConversationRowView) -> Bool {
        lhs.rowSignature == rhs.rowSignature
    }

    private var rowSignature: WatchConversationRowSignature {
        WatchConversationRowSignature(
            id: conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            isFavorite: conversation.isFavorite,
            previewText: conversation.previewText,
            messageCount: conversation.messageCount,
            containsAudioAttachments: conversation.containsAudioAttachments,
            containsImageAttachments: conversation.containsImageAttachments,
            aiConfiguration: aiConfiguration
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)

                if conversation.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer(minLength: 4)

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(conversation.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ViewThatFits(in: .horizontal) {
                metaLine(includeAttachments: true, includeThinking: true)
                metaLine(includeAttachments: false, includeThinking: true)
                metaLine(includeAttachments: false, includeThinking: false)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.cyan.opacity(0.9))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func metaLine(
        includeAttachments: Bool,
        includeThinking: Bool
    ) -> some View {
        HStack(spacing: 5) {
            WatchConversationMetaItem(
                iconName: "bubble.left.and.bubble.right",
                title: "\(conversation.messageCount)"
            )

            if includeAttachments, conversation.containsAudioAttachments {
                WatchConversationMetaItem(iconName: "waveform")
            }

            if includeAttachments, conversation.containsImageAttachments {
                WatchConversationMetaItem(iconName: "photo")
            }

            WatchConversationMetaItem(
                iconName: "cpu",
                title: AIModelCatalog.shortLabel(for: aiConfiguration.model)
            )

            if includeThinking {
                WatchConversationMetaItem(
                    iconName: "brain.head.profile",
                    title: aiConfiguration.thinkingIntensity.shortLabel
                )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }
}

private struct WatchConversationRowSignature: Equatable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let isFavorite: Bool
    let previewText: String
    let messageCount: Int
    let containsAudioAttachments: Bool
    let containsImageAttachments: Bool
    let aiConfiguration: ConversationAIConfiguration
}

private struct WatchConversationMetaItem: View {
    let iconName: String
    var title: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .imageScale(.small)

            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .monospacedDigit()
            }
        }
    }
}
