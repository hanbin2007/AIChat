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

    var body: some View {
        ZStack {
            AppBackdropView()

            List {
                if chatStore.configuration.isGeminiConfigured == false {
                    ConfigurationBannerView(message: chatStore.configuration.configurationMessage)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

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
                            ConversationRowView(conversation: conversation)
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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AIChat")
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
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built for Watch")
                .font(.headline)

            Text("Context-aware Gemini chat, photo prompts, and fast handoff between threads.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    let newConversationID = await chatStore.createConversation()
                    navigationPath = [newConversationID]
                }
            } label: {
                Label("Start Chat", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
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
                if conversation.messages.contains(where: { $0.attachments.isEmpty == false }) {
                    Label("Photo", systemImage: "photo")
                        .labelStyle(.titleAndIcon)
                }
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
