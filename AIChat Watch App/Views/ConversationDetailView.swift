//
//  ConversationDetailView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import PhotosUI
import SwiftUI

struct ConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        ZStack {
            AppBackdropView()

            if let conversation = chatStore.conversation(id: conversationID) {
                VStack(spacing: 8) {
                    messagesView(conversation: conversation)
                    composerView
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "trash.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Conversation not found")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle(chatStore.conversation(id: conversationID)?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await importPickedItems(newItems)
            }
        }
    }

    private func messagesView(conversation: ConversationThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        starterCard
                    } else {
                        ForEach(conversation.messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }

                    if chatStore.isSending(conversationID: conversationID) {
                        HStack {
                            ProgressView()
                                .tint(.cyan)
                            Text("Gemini is thinking")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }

                    if let errorMessage = chatStore.errorMessage(for: conversationID) {
                        ConfigurationBannerView(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Send Failed",
                            message: errorMessage
                        )
                        .id("error")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                scrollToBottom(with: proxy)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(with: proxy)
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _, _ in
                scrollToBottom(with: proxy)
            }
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start with anything")
                .font(.headline)

            Text("Ask a question, dictate a prompt, or attach a photo for visual analysis.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                starterChip("Summarize notes")
                starterChip("Explain this photo")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func starterChip(_ text: String) -> some View {
        Button(text) {
            chatStore.updateDraftText(text, for: conversationID)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.8))
        .font(.caption2)
    }

    private var composerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chatStore.draftAttachments(for: conversationID).isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatStore.draftAttachments(for: conversationID)) { attachment in
                            DraftAttachmentPill(
                                attachment: attachment,
                                onRemove: {
                                    chatStore.removeAttachment(id: attachment.id, from: conversationID)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            TextField(
                "Ask Gemini",
                text: Binding(
                    get: { chatStore.draftText(for: conversationID) },
                    set: { chatStore.updateDraftText($0, for: conversationID) }
                ),
                prompt: Text("Ask Gemini")
            )
            .textInputAutocapitalization(.sentences)
            .submitLabel(.send)
            .onSubmit {
                Task {
                    await chatStore.sendMessage(in: conversationID)
                }
            }

            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label("Photo", systemImage: "photo.on.rectangle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.8))

                Button {
                    chatStore.clearError(for: conversationID)
                    Task {
                        await chatStore.sendMessage(in: conversationID)
                    }
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(
                    chatStore.isSending(conversationID: conversationID) ||
                    (
                        chatStore.draftText(for: conversationID).nonEmptyTrimmed == nil &&
                        chatStore.draftAttachments(for: conversationID).isEmpty
                    )
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @MainActor
    private func importPickedItems(_ items: [PhotosPickerItem]) async {
        guard items.isEmpty == false else {
            return
        }

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                try chatStore.addAttachment(
                    from: data,
                    suggestedFilename: "photo",
                    to: conversationID
                )
            } catch {
                chatStore.presentError(error.localizedDescription, for: conversationID)
            }
        }

        selectedPhotoItems = []
    }

    private func scrollToBottom(with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct DraftAttachmentPill: View {
    let attachment: ChatImageAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .offset(x: 4, y: -4)
        }
    }
}
