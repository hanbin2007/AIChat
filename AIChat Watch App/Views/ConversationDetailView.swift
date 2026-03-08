//
//  ConversationDetailView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import PhotosUI
import SwiftUI
import UIKit

private enum ComposerLayout {
    static let messagesToComposerSpacing: CGFloat = 4
    static let expandedBottomInset: CGFloat = 1
    static let collapsedBottomInset: CGFloat = 56
    static let containerBottomPadding: CGFloat = 0
    static let composerInnerBottomPadding: CGFloat = 4
    static let collapsedButtonBottomPadding: CGFloat = 8
    static let regularComposerSpacing: CGFloat = 9
    static let compactComposerSpacing: CGFloat = 8
    static let regularAttachmentSize: CGFloat = 60
    static let compactAttachmentSize: CGFloat = 44
    static let regularInputRowHeight: CGFloat = 44
    static let compactInputRowHeight: CGFloat = 40
    static let actionButtonSizeDelta: CGFloat = 1
    static let regularActionButtonSize: CGFloat = regularInputRowHeight + actionButtonSizeDelta
    static let compactActionButtonSize: CGFloat = compactInputRowHeight + actionButtonSizeDelta
    static let regularInputRowSpacing: CGFloat = 8
    static let compactInputRowSpacing: CGFloat = 8
}

struct ConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @StateObject private var voiceRecorder = VoiceRecorder()
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
                    VStack(spacing: ComposerLayout.messagesToComposerSpacing) {
                        messagesView(conversation: conversation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        if isComposerExpanded {
                            composerView()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 6)
                    .padding(.bottom, ComposerLayout.containerBottomPadding)

                    if isComposerExpanded == false {
                        collapsedComposerButton
                            .padding(.trailing, 10)
                            .padding(.bottom, ComposerLayout.collapsedButtonBottomPadding)
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
        .onChange(of: voiceRecorder.completedAttachment) { _, attachment in
            guard let attachment else {
                return
            }

            handleRecordedAttachment(attachment)
        }
        .onChange(of: voiceRecorder.errorMessage) { _, errorMessage in
            guard let errorMessage else {
                return
            }

            chatStore.presentError(errorMessage, for: conversationID)
            voiceRecorder.clearError()
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
                        .frame(height: isComposerExpanded ? ComposerLayout.expandedBottomInset : ComposerLayout.collapsedBottomInset)
                        .id("bottom")
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(with: proxy, animated: true)
            }
            .onChange(of: conversation.updatedAt) { _, _ in
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _, _ in
                scrollToBottom(with: proxy, animated: false)
            }
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start with anything")
                .font(.headline)

            Text("Ask a question, record a voice prompt that will be transcribed automatically, or attach a photo for visual analysis.")
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

    private func composerView() -> some View {
        let aiConfiguration = chatStore.aiConfiguration(for: conversationID)
        let attachments = chatStore.draftAttachments(for: conversationID)
        let draftText = chatStore.draftText(for: conversationID)
        let hasAttachments = attachments.isEmpty == false
        let hasDraftContent = draftText.nonEmptyTrimmed != nil || hasAttachments
        let isTranscribing = chatStore.isTranscribing(conversationID: conversationID)
        let inputRowHeight = hasAttachments ? ComposerLayout.compactInputRowHeight : ComposerLayout.regularInputRowHeight
        let actionButtonSize = hasAttachments ? ComposerLayout.compactActionButtonSize : ComposerLayout.regularActionButtonSize
        let sendEnabled =
            chatStore.isSending(conversationID: conversationID) == false &&
            isTranscribing == false &&
            voiceRecorder.isInteractive &&
            hasDraftContent

        return VStack(alignment: .leading, spacing: hasAttachments ? ComposerLayout.compactComposerSpacing : ComposerLayout.regularComposerSpacing) {
            compactControlBar(
                configuration: aiConfiguration,
                isDense: hasAttachments
            )

            if hasAttachments {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: hasAttachments ? 6 : 8) {
                        ForEach(attachments) { attachment in
                            DraftAttachmentPill(
                                attachment: attachment,
                                size: hasAttachments ? ComposerLayout.compactAttachmentSize : ComposerLayout.regularAttachmentSize,
                                onRemove: {
                                    chatStore.removeAttachment(id: attachment.id, from: conversationID)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: hasAttachments ? ComposerLayout.compactAttachmentSize : ComposerLayout.regularAttachmentSize)
            }

            if voiceRecorder.isRecording || voiceRecorder.isPreparing {
                RecordingStatusBanner(
                    iconName: voiceRecorder.isRecording ? "waveform.circle.fill" : "mic.circle",
                    title: voiceRecorder.isRecording ? "Recording \(voiceRecorder.elapsedTimeText)" : "Preparing microphone...",
                    tint: voiceRecorder.isRecording ? .red : .white.opacity(0.82)
                )
            } else if isTranscribing {
                RecordingStatusBanner(
                    iconName: "waveform.and.magnifyingglass",
                    title: "Transcribing with \(AIModelCatalog.shortLabel(for: chatStore.configuration.geminiTranscriptionModel))...",
                    tint: .cyan
                )
            }

            HStack(spacing: hasAttachments ? ComposerLayout.compactInputRowSpacing : ComposerLayout.regularInputRowSpacing) {
                TextFieldLink(prompt: Text("Ask Gemini")) {
                    Text(draftText.nonEmptyTrimmed ?? "Ask Gemini")
                        .lineLimit(1)
                        .truncationMode(.tail)
                } onSubmit: { submittedText in
                    chatStore.updateDraftText(submittedText, for: conversationID)
                }
                .frame(maxWidth: .infinity, minHeight: inputRowHeight, alignment: .leading)
                .accessibilityLabel("Compose message")
                .disabled(voiceRecorder.isRecording || isTranscribing)

                Button {
                    toggleVoiceRecording()
                } label: {
                    ComposerActionButtonLabel(
                        systemName: voiceRecorder.isRecording ? "stop.fill" : "waveform.badge.mic",
                        dimension: actionButtonSize,
                        fillStyle: AnyShapeStyle(
                            voiceRecorder.isRecording ?
                            Color.red.opacity(0.94) :
                            Color.white.opacity(0.11)
                        ),
                        strokeColor: Color.white.opacity(voiceRecorder.isRecording ? 0.14 : 0.08)
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: actionButtonSize,
                    height: actionButtonSize
                )
                .disabled(
                    voiceRecorder.isRecording == false &&
                    (
                        chatStore.isSending(conversationID: conversationID) ||
                        isTranscribing ||
                        voiceRecorder.isPreparing ||
                        hasDraftContent
                    )
                )
                .accessibilityLabel(voiceRecorder.isRecording ? "Stop recording and send" : "Record voice message")

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    ComposerActionButtonLabel(
                        systemName: "photo.on.rectangle",
                        dimension: actionButtonSize,
                        fillStyle: AnyShapeStyle(Color.white.opacity(0.11)),
                        strokeColor: Color.white.opacity(0.08)
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: actionButtonSize,
                    height: actionButtonSize
                )
                .disabled(voiceRecorder.isRecording || isTranscribing)
                .accessibilityLabel("Add photo")

                Button {
                    sendCurrentDraft()
                } label: {
                    ComposerActionButtonLabel(
                        systemName: "arrow.up.circle.fill",
                        dimension: actionButtonSize,
                        fillStyle: AnyShapeStyle(Color.cyan.opacity(sendEnabled ? 0.96 : 0.42)),
                        strokeColor: Color.white.opacity(sendEnabled ? 0.10 : 0.05)
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: actionButtonSize,
                    height: actionButtonSize
                )
                .disabled(sendEnabled == false)
                .accessibilityLabel("Send")
            }
        }
        .padding(.top, hasAttachments ? 6 : 8)
        .padding(.horizontal, hasAttachments ? 6 : 8)
        .padding(.bottom, (hasAttachments ? 6 : 8) + ComposerLayout.composerInnerBottomPadding)
        .background(
            RoundedRectangle(cornerRadius: hasAttachments ? 20 : 22, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: hasAttachments ? 20 : 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: hasAttachments ? 20 : 22, style: .continuous))
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

    private func compactControlBar(configuration: ConversationAIConfiguration, isDense: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                isShowingModelPicker = true
            } label: {
                CompactMenuButtonLabel(
                    iconName: "cpu",
                    title: AIModelCatalog.shortLabel(for: configuration.model),
                    isDense: isDense
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                isShowingThinkingPicker = true
            } label: {
                CompactMenuButtonLabel(
                    iconName: "brain.head.profile",
                    title: configuration.thinkingIntensity.shortLabel,
                    isDense: isDense
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

    private func toggleVoiceRecording() {
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
            return
        }

        chatStore.clearError(for: conversationID)

        Task {
            await voiceRecorder.startRecording()
        }
    }

    private func handleRecordedAttachment(_ attachment: ChatAttachment) {
        voiceRecorder.consumeCompletedAttachment()

        Task {
            await chatStore.sendRecordedAudio(attachment, in: conversationID)
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func sendCurrentDraft() {
        guard chatStore.isSending(conversationID: conversationID) == false,
              chatStore.isTranscribing(conversationID: conversationID) == false
        else {
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
    let isDense: Bool

    private var leadingIconPointSize: CGFloat {
        isDense ? 13 : 14
    }

    private var leadingIconFrameSize: CGFloat {
        isDense ? 14 : 16
    }

    private var leadingIconScale: CGFloat {
        iconName == "cpu" ? 1.12 : 1.0
    }

    private var titlePointSize: CGFloat {
        isDense ? 13 : 14
    }

    var body: some View {
        HStack(spacing: isDense ? 4 : 5) {
            Image(systemName: iconName)
                .font(.system(size: leadingIconPointSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan.opacity(0.92))
                .frame(width: leadingIconFrameSize, height: leadingIconFrameSize)
                .scaleEffect(leadingIconScale)

            Text(title)
                .font(.system(size: titlePointSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: isDense ? 9 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: isDense ? 8 : 10)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, isDense ? 6 : 8)
        .padding(.vertical, isDense ? 6 : 8)
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

private struct ComposerActionButtonLabel: View {
    let systemName: String
    let dimension: CGFloat
    let fillStyle: AnyShapeStyle
    let strokeColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: dimension * 0.36, style: .continuous)
            .fill(fillStyle)
            .overlay(
                RoundedRectangle(cornerRadius: dimension * 0.36, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: dimension * 0.40, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

private struct RecordingStatusBanner: View {
    let iconName: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DraftAttachmentPill: View {
    let attachment: ChatAttachment
    let size: CGFloat
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = attachment.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.18, blue: 0.24),
                                Color(red: 0.03, green: 0.43, blue: 0.51)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Image(systemName: attachment.isAudio ? "waveform" : "paperclip")
                                .font(size <= ComposerLayout.compactAttachmentSize ? .caption2 : .caption)
                                .foregroundStyle(.white.opacity(0.9))

                            if let durationText = formattedDuration {
                                Text(durationText)
                                    .font(.system(size: size <= ComposerLayout.compactAttachmentSize ? 9 : 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                        }
                        .padding(size <= ComposerLayout.compactAttachmentSize ? 6 : 8)
                    }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(size <= ComposerLayout.compactAttachmentSize ? .caption2 : .caption)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .offset(x: size <= ComposerLayout.compactAttachmentSize ? 3 : 4, y: size <= ComposerLayout.compactAttachmentSize ? -3 : -4)
        }
    }

    private var formattedDuration: String? {
        guard let durationSeconds = attachment.durationSeconds, durationSeconds > 0 else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: durationSeconds)
    }
}

#if DEBUG
private enum ConversationDetailPreviewData {
    static let conversationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 763_344_000)

    static let conversation = ConversationThread(
        id: conversationID,
        title: "Trip Planning",
        createdAt: baseDate,
        updatedAt: baseDate.addingTimeInterval(240),
        messages: [
            ChatMessage(
                id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee1")!,
                role: .user,
                text: "Summarize our Tokyo plan and keep the must-see stops.",
                createdAt: baseDate
            ),
            ChatMessage(
                id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee2")!,
                role: .assistant,
                text: "You have three anchor stops right now: Asakusa in the morning, the Shibuya and Harajuku area in the afternoon, and a quieter evening in Nakameguro. I would keep teamLab Borderless as the one pre-booked activity and leave the second day flexible for food and shopping.",
                thoughtSummary: "Grouped the itinerary by area, removed repeated transport notes, and kept only places that already had clear intent.",
                createdAt: baseDate.addingTimeInterval(90)
            ),
            ChatMessage(
                id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee3")!,
                role: .user,
                text: "Also check this screenshot and tell me if the route still makes sense.",
                createdAt: baseDate.addingTimeInterval(180),
                attachments: [
                    placeholderAttachment(
                        id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-fffffffffff1")!,
                        filename: "tokyo-route.png"
                    )
                ]
            ),
            ChatMessage(
                id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee4")!,
                role: .assistant,
                text: "Yes. The route is still coherent if you keep Asakusa first, then move west only once for the rest of the day. The biggest improvement would be swapping Shinjuku Gyoen and Harajuku so the walking flow is tighter.",
                thoughtSummary: "Compared the screenshot ordering against the earlier plan and looked for unnecessary backtracking.",
                createdAt: baseDate.addingTimeInterval(240)
            )
        ],
        aiConfiguration: ConversationAIConfiguration(
            model: "gemini-3.1-pro-preview",
            thinkingIntensity: .deep
        )
    )

    static var draft: ConversationDraft {
        ConversationDraft(
            text: "Turn that into a tighter day-one itinerary with breakfast and dinner suggestions.",
            attachments: [
                placeholderAttachment(
                    id: UUID(uuidString: "bbbbbbbb-cccc-dddd-eeee-fffffffffff2")!,
                    filename: "food-notes.png"
                )
            ]
        )
    }

    static func makeStore() -> ChatStore {
        ChatStore.previewStore(
            conversations: [conversation],
            drafts: [conversationID: draft]
        )
    }

    private static func placeholderAttachment(id: UUID, filename: String) -> ChatImageAttachment {
        let symbolName = filename.contains("route") ? "map.fill" : "fork.knife.circle.fill"
        let previewImage = UIImage(systemName: symbolName)?
            .withTintColor(
                UIColor(red: 0.12, green: 0.76, blue: 0.72, alpha: 1),
                renderingMode: .alwaysOriginal
            )

        return ChatImageAttachment(
            id: id,
            kind: .image,
            filename: filename,
            mimeType: "image/png",
            data: previewImage?.pngData() ?? Data(),
            pixelWidth: Int(previewImage?.size.width ?? 320),
            pixelHeight: Int(previewImage?.size.height ?? 320)
        )
    }
}

private struct ConversationDetailPreviewContainer: View {
    @StateObject private var chatStore = ConversationDetailPreviewData.makeStore()

    var body: some View {
        NavigationStack {
            ConversationDetailView(conversationID: ConversationDetailPreviewData.conversationID)
        }
        .environmentObject(chatStore)
    }
}

#Preview("Conversation Detail") {
    ConversationDetailPreviewContainer()
}
#endif
