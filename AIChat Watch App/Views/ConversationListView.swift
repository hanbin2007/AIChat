//
//  ConversationListView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

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
                    if chatStore.isReadOnlyMode {
                        ForEach(chatStore.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRowView(
                                    conversation: conversation,
                                    aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        ForEach(chatStore.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRowView(
                                    conversation: conversation,
                                    aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                                )
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { offsets in
                            Task {
                                await chatStore.deleteConversations(at: offsets)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AIChat")
        .sheet(isPresented: $isShowingActivationCenter) {
            ActivationCenterView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        let newConversationID = await chatStore.createConversation()
                        navigationPath = [newConversationID]
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New conversation")
                .disabled(chatStore.isReadOnlyMode)
            }
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
    }
}

private struct ConversationRowView: View {
    let conversation: ConversationThread
    let aiConfiguration: ConversationAIConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Text(conversation.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(conversation.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Label("\(conversation.messageCount)", systemImage: "bubble.left.and.bubble.right")
                    .labelStyle(.titleAndIcon)
                if conversation.messages.contains(where: { $0.attachments.contains(where: \.isAudio) }) {
                    Label("Voice", systemImage: "waveform")
                        .labelStyle(.titleAndIcon)
                }
                if conversation.messages.contains(where: { $0.attachments.contains(where: \.isImage) }) {
                    Label("Photo", systemImage: "photo")
                        .labelStyle(.titleAndIcon)
                }
                Text(AIModelCatalog.shortLabel(for: aiConfiguration.model))
                Text("•")
                Text(aiConfiguration.thinkingIntensity.shortLabel)
            }
            .font(.caption2)
            .foregroundStyle(.cyan)
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
}
