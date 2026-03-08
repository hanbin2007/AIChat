//
//  ConversationDetailView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import PhotosUI
import SwiftUI

private enum ComposerLayout {
    static let collapsedBottomInset: CGFloat = 56
}

struct ConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var isShowingModelPicker = false
    @State private var isShowingThinkingPicker = false
    @State private var isComposerExpanded = true

    var body: some View {
        ZStack {
            AppBackdropView()

            if let conversation = chatStore.conversation(id: conversationID) {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: 8) {
                        messagesView(conversation: conversation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        if isComposerExpanded {
                            composerView(conversation: conversation)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)

                    if isComposerExpanded == false {
                        collapsedComposerButton
                            .padding(.trailing, 10)
                            .padding(.bottom, 8)
                            .transition(.scale.combined(with: .opacity))
                    }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation settings")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ConversationSettingsView(conversationID: conversationID)
        }
        .confirmationDialog("Choose Model", isPresented: $isShowingModelPicker) {
            ForEach(AIModelCatalog.quickOptions(defaultModel: chatStore.configuration.geminiModel)) { option in
                Button(option.title) {
                    Task {
                        await chatStore.updateModel(option.id, for: conversationID)
                    }
                }
            }
        }
        .confirmationDialog("Thinking Mode", isPresented: $isShowingThinkingPicker) {
            ForEach(AIThinkingIntensity.allCases) { intensity in
                Button(intensity.displayName) {
                    Task {
                        await chatStore.updateThinkingIntensity(intensity, for: conversationID)
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await importPickedItems(newItems)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isComposerExpanded)
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

                    if let errorMessage = chatStore.errorMessage(for: conversationID) {
                        ConfigurationBannerView(
                            iconName: "exclamationmark.triangle.fill",
                            title: "Send Failed",
                            message: errorMessage
                        )
                        .id("error")
                    }

                    Color.clear
                        .frame(height: isComposerExpanded ? 1 : ComposerLayout.collapsedBottomInset)
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
            .onChange(of: conversation.updatedAt) { _, _ in
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

            VStack(alignment: .leading, spacing: 6) {
                starterChip("Summarize notes")
                starterChip("Explain this photo")
            }
        }
        .padding(12)
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
        .controlSize(.small)
        .tint(.white.opacity(0.8))
        .font(.caption2)
    }

    private func composerView(conversation: ConversationThread) -> some View {
        let aiConfiguration = conversation.resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)

        return VStack(alignment: .leading, spacing: 8) {
            compactControlBar(configuration: aiConfiguration)

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
            .font(.body)
            .onSubmit {
                sendCurrentDraft()
            }

            HStack(spacing: 6) {
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    Label("Photo", systemImage: "photo.on.rectangle")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.white.opacity(0.8))
                .frame(width: 52)

                Button {
                    sendCurrentDraft()
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard isPredominantlyVertical(value.translation) else {
                        return
                    }

                    if value.translation.height > 24 {
                        collapseComposer()
                    }
                }
        )
    }

    private var collapsedComposerButton: some View {
        Button {
            expandComposer()
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(Color.cyan.opacity(0.92))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open composer")
    }

    private func compactControlBar(configuration: ConversationAIConfiguration) -> some View {
        HStack(spacing: 6) {
            Button {
                isShowingModelPicker = true
            } label: {
                CompactMenuButtonLabel(
                    iconName: "cpu",
                    title: AIModelCatalog.shortLabel(for: configuration.model)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                isShowingThinkingPicker = true
            } label: {
                CompactMenuButtonLabel(
                    iconName: "brain.head.profile",
                    title: configuration.thinkingIntensity.shortLabel
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
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

    private func sendCurrentDraft() {
        guard chatStore.isSending(conversationID: conversationID) == false else {
            return
        }

        let draft = ConversationDraft(
            text: chatStore.draftText(for: conversationID),
            attachments: chatStore.draftAttachments(for: conversationID)
        )

        guard draft.hasContent else {
            return
        }

        if chatStore.configuration.isAIConfigured {
            collapseComposer()
        }

        chatStore.clearError(for: conversationID)

        Task {
            await chatStore.sendMessage(in: conversationID)
        }
    }

    private func collapseComposer() {
        guard isComposerExpanded else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isComposerExpanded = false
        }
    }

    private func expandComposer() {
        guard isComposerExpanded == false else {
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isComposerExpanded = true
        }
    }

    private func isPredominantlyVertical(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width)
    }
}

private struct CompactMenuButtonLabel: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(.cyan.opacity(0.92))

            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
