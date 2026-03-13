//
//  ConversationDetailView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

#if os(watchOS)
import PhotosUI
import SwiftUI
import UIKit

private enum ComposerLayout {
    static let messagesToComposerSpacing: CGFloat = 4
    static let expandedBottomInset: CGFloat = 1
    static let collapsedBottomInset: CGFloat = 56
    static let containerBottomPadding: CGFloat = 16
    static let composerInnerBottomPadding: CGFloat = 0
    static let collapsedButtonBottomPadding: CGFloat = 16
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
    static let flatActionButtonHeight: CGFloat = 30
    static let flatActionRowSpacing: CGFloat = 6
}

private enum ConversationScrollLayout {
    static let bottomAnchorID = "conversation-bottom-anchor"
    static let coordinateSpaceName = "conversation-messages-scroll"
    static let interruptionThreshold: CGFloat = 28
    static let suppressionDuration: TimeInterval = 0.28
}

private enum VoiceCaptureMode {
    case transcribe
    case directSend
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
    @State private var isShowingActivationCenter = false
    @State private var interruptedAutoScrollMessageID: UUID?
    @State private var scrollInterruptionsSuppressedUntil = Date.distantPast
    @State private var messagesViewportHeight: CGFloat = 0
    @State private var voiceCaptureMode: VoiceCaptureMode = .transcribe
    @State private var suppressedVoiceTapUntil = Date.distantPast

    var body: some View {
        ZStack {
            AppBackdropView()

            if let conversation = chatStore.conversation(id: conversationID) {
                ZStack(alignment: .bottomTrailing) {
                    VStack(spacing: ComposerLayout.messagesToComposerSpacing) {
                        messagesView(conversation: conversation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        if isComposerExpanded {
                            Group {
                                if chatStore.isReadOnlyMode {
                                    lockedComposerView
                                } else {
                                    composerView()
                                }
                            }
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
                .ignoresSafeArea(.container, edges: .bottom)
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
        .sheet(isPresented: $isShowingActivationCenter) {
            ActivationCenterView()
        }
        .confirmationDialog("Choose Model", isPresented: $isShowingModelPicker) {
            ForEach(chatStore.availableModelOptions()) { option in
                Button(option.title) {
                    Task {
                        await chatStore.updateModel(option.id, for: conversationID)
                    }
                }
            }
        }
        .confirmationDialog("Thinking Mode", isPresented: $isShowingThinkingPicker) {
            ForEach(chatStore.availableThinkingIntensities(for: conversationID)) { intensity in
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
        let streamingMessageID = currentStreamingMessageID(in: conversation)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        starterCard
                    } else {
                        ForEach(conversation.messages) { message in
                            ChatBubbleView(conversationID: conversationID, message: message)
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
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ConversationBottomAnchorMaxYPreferenceKey.self,
                                    value: geometry.frame(in: .named(ConversationScrollLayout.coordinateSpaceName)).maxY
                                )
                            }
                        )
                        .id(ConversationScrollLayout.bottomAnchorID)
                }
                .padding(.horizontal, 4)
            }
            .coordinateSpace(name: ConversationScrollLayout.coordinateSpaceName)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ConversationViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if chatStore.canRetryLatestReply(in: conversationID) {
                    retryButton
                        .padding(.trailing, 8)
                        .padding(.bottom, isComposerExpanded ? 12 : 62)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width),
                              abs(value.translation.height) > 6
                        else {
                            return
                        }

                        interruptAutoScroll(for: streamingMessageID)
                    }
            )
            .onPreferenceChange(ConversationViewportHeightPreferenceKey.self) { height in
                messagesViewportHeight = height
            }
            .onPreferenceChange(ConversationBottomAnchorMaxYPreferenceKey.self) { maxY in
                handleBottomAnchorPositionChange(maxY, streamingMessageID: streamingMessageID)
            }
            .onAppear {
                interruptedAutoScrollMessageID = nil
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID,
                    force: true
                )
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: true,
                    streamingMessageID: streamingMessageID
                )
            }
            .onChange(of: conversation.updatedAt) { _, _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID
                )
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _, _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID
                )
            }
            .onChange(of: streamingMessageID) { _, newMessageID in
                interruptedAutoScrollMessageID = nil
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: newMessageID,
                    force: true
                )
            }
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chatStore.isReadOnlyMode ? "只读模式" : "Ask Anything")
                .font(.headline)

            Text(
                chatStore.isReadOnlyMode ?
                "先看历史消息；激活后再发消息或传图。" :
                "Type, speak, or add a photo."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)

            if chatStore.isReadOnlyMode {
                Button("Activate on Watch") {
                    isShowingActivationCenter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    starterChip("Summarize notes")
                    starterChip("Explain this photo")
                }
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
        let isSendingReply = chatStore.isSending(conversationID: conversationID)
        let inputRowHeight = hasAttachments ? ComposerLayout.compactInputRowHeight : ComposerLayout.regularInputRowHeight
        let sendButtonSize = hasAttachments ? ComposerLayout.compactActionButtonSize : ComposerLayout.regularActionButtonSize
        let sendEnabled =
            isSendingReply == false &&
            isTranscribing == false &&
            voiceRecorder.isInteractive &&
            hasDraftContent
        let voiceButtonLabel =
            voiceRecorder.isRecording ?
            (voiceCaptureMode == .directSend ? "Stop & Send" : "Stop & Transcribe") :
            "Voice"
        let voiceButtonDisabled =
            voiceRecorder.isRecording == false &&
            (
                chatStore.isSending(conversationID: conversationID) ||
                isTranscribing ||
                voiceRecorder.isPreparing
            )

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
                    title: voiceRecorder.isRecording ?
                        recordingStatusTitle() :
                        L10n.tr("conversation.microphone.preparing"),
                    tint: voiceRecorder.isRecording ? .red : .white.opacity(0.82)
                )
            } else if isTranscribing {
                RecordingStatusBanner(
                    iconName: "waveform.and.magnifyingglass",
                    title: L10n.format(
                        "conversation.transcribing",
                        AITranscriptionModelCatalog.shortLabel(for: chatStore.selectedTranscriptionModel)
                    ),
                    tint: .cyan
                )
            }

            HStack(spacing: hasAttachments ? ComposerLayout.compactInputRowSpacing : ComposerLayout.regularInputRowSpacing) {
                TextField("Ask Gemini", text: draftTextBinding())
                .frame(maxWidth: .infinity, minHeight: inputRowHeight, alignment: .leading)
                .accessibilityLabel("Compose message")
                .disabled(voiceRecorder.isRecording || isTranscribing)

                Button {
                    if isSendingReply {
                        stopCurrentReply()
                    } else {
                        sendCurrentDraft()
                    }
                } label: {
                    ComposerActionButtonLabel(
                        systemName: isSendingReply ? "stop.fill" : "arrow.up.circle.fill",
                        dimension: sendButtonSize,
                        fillStyle: AnyShapeStyle(
                            isSendingReply ? Color.red.opacity(0.94) : Color.cyan.opacity(sendEnabled ? 0.96 : 0.42)
                        ),
                        strokeColor: Color.white.opacity(isSendingReply ? 0.16 : (sendEnabled ? 0.10 : 0.05))
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: sendButtonSize,
                    height: sendButtonSize
                )
                .disabled(isSendingReply ? false : sendEnabled == false)
                .accessibilityLabel(isSendingReply ? "Stop response" : "Send")
            }

            HStack(spacing: ComposerLayout.flatActionRowSpacing) {
                Button {
                    handleVoiceButtonTap()
                } label: {
                    ComposerFlatActionButtonLabel(
                        systemName: voiceRecorder.isRecording ? "stop.fill" : "waveform.badge.mic",
                        title: voiceButtonLabel,
                        tintColor: voiceRecorder.isRecording ? .red : .white
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(voiceButtonDisabled)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            handleVoiceButtonLongPress()
                        }
                )
                .accessibilityLabel(
                    voiceRecorder.isRecording ?
                    (voiceCaptureMode == .directSend ? "Stop recording and send audio" : "Stop recording and transcribe") :
                    "Record voice message"
                )
                .accessibilityHint("Long press to send the recorded audio directly.")

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    ComposerFlatActionButtonLabel(
                        systemName: "photo.on.rectangle",
                        title: "Photo",
                        tintColor: .white
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(voiceRecorder.isRecording || isTranscribing)
                .accessibilityLabel("Add photo")
            }
        }
        .padding(.top, hasAttachments ? 6 : 8)
        .padding(.horizontal, hasAttachments ? 6 : 8)
        .padding(.bottom, (hasAttachments ? 4 : 5) + ComposerLayout.composerInnerBottomPadding)
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

    private var lockedComposerView: some View {
        ActivationStatusCard(
            title: "发送已锁定",
            message: chatStore.activationStatusMessage,
            iconName: "lock.fill",
            accentColor: .orange,
            actionTitle: "输入激活码"
        ) {
            isShowingActivationCenter = true
        }
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

    private var retryButton: some View {
        Button {
            retryLatestReply()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.68))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry last reply")
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

    private func handleVoiceButtonTap() {
        guard Date.now >= suppressedVoiceTapUntil else {
            return
        }

        toggleVoiceRecording(startMode: .transcribe)
    }

    private func handleVoiceButtonLongPress() {
        guard voiceRecorder.isRecording == false,
              chatStore.isSending(conversationID: conversationID) == false,
              chatStore.isTranscribing(conversationID: conversationID) == false,
              voiceRecorder.isPreparing == false
        else {
            return
        }

        suppressedVoiceTapUntil = Date.now.addingTimeInterval(0.75)
        toggleVoiceRecording(startMode: .directSend)
    }

    private func toggleVoiceRecording(startMode: VoiceCaptureMode) {
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
            return
        }

        voiceCaptureMode = startMode
        chatStore.clearError(for: conversationID)

        Task {
            await voiceRecorder.startRecording()
        }
    }

    private func handleRecordedAttachment(_ attachment: ChatAttachment) {
        let captureMode = voiceCaptureMode
        voiceCaptureMode = .transcribe
        voiceRecorder.consumeCompletedAttachment()

        Task {
            switch captureMode {
            case .transcribe:
                await chatStore.sendRecordedAudio(attachment, in: conversationID)
            case .directSend:
                collapseComposer()
                await chatStore.sendRecordedAudioDirectly(attachment, in: conversationID)
            }
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        scrollInterruptionsSuppressedUntil = Date.now.addingTimeInterval(ConversationScrollLayout.suppressionDuration)

        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(ConversationScrollLayout.bottomAnchorID, anchor: .bottom)
            }
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(ConversationScrollLayout.bottomAnchorID, anchor: .bottom)
        }
    }

    private func currentStreamingMessageID(in conversation: ConversationThread) -> UUID? {
        conversation.messages.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
    }

    private func scrollToBottomIfNeeded(
        with proxy: ScrollViewProxy,
        animated: Bool,
        streamingMessageID: UUID?,
        force: Bool = false
    ) {
        guard force || shouldAutoScroll(for: streamingMessageID) else {
            return
        }

        scrollToBottom(with: proxy, animated: animated)
    }

    private func shouldAutoScroll(for streamingMessageID: UUID?) -> Bool {
        guard let streamingMessageID else {
            return true
        }

        return interruptedAutoScrollMessageID != streamingMessageID
    }

    private func interruptAutoScroll(for streamingMessageID: UUID?) {
        guard let streamingMessageID else {
            return
        }

        interruptedAutoScrollMessageID = streamingMessageID
    }

    private func handleBottomAnchorPositionChange(_ maxY: CGFloat, streamingMessageID: UUID?) {
        guard let streamingMessageID,
              Date.now >= scrollInterruptionsSuppressedUntil,
              messagesViewportHeight > 0
        else {
            return
        }

        let distanceFromBottom = maxY - messagesViewportHeight
        guard distanceFromBottom > ConversationScrollLayout.interruptionThreshold else {
            return
        }

        interruptAutoScroll(for: streamingMessageID)
    }

    private func sendCurrentDraft() {
        guard chatStore.isReadOnlyMode == false else {
            isShowingActivationCenter = true
            return
        }

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

        chatStore.clearError(for: conversationID)
        collapseComposer()

        Task {
            await chatStore.sendMessage(in: conversationID)
        }
    }

    private func retryLatestReply() {
        guard chatStore.isReadOnlyMode == false else {
            isShowingActivationCenter = true
            return
        }

        guard chatStore.canRetryLatestReply(in: conversationID) else {
            return
        }

        chatStore.clearError(for: conversationID)

        Task {
            await chatStore.retryLatestReply(in: conversationID)
        }
    }

    private func stopCurrentReply() {
        chatStore.stopSending(in: conversationID)
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

    private func recordingStatusTitle() -> String {
        let duration = L10n.format("conversation.recording", voiceRecorder.elapsedTimeText)
        guard voiceCaptureMode == .directSend else {
            return duration
        }

        return "Send Voice | \(duration)"
    }

    private func draftTextBinding() -> Binding<String> {
        Binding(
            get: {
                chatStore.draftText(for: conversationID)
            },
            set: { newValue in
                chatStore.updateDraftText(newValue, for: conversationID)
            }
        )
    }
}

private struct ConversationViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ConversationBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

            OverflowScrollingText(
                text: title,
                font: .system(size: titlePointSize, weight: .semibold, design: .rounded),
                color: .white,
                gap: 16,
                speed: 24,
                expandsHorizontally: true
            )
            .layoutPriority(1)

            Image(systemName: "chevron.down")
                .font(.system(size: isDense ? 9 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: isDense ? 8 : 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ComposerFlatActionButtonLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let systemName: String
    let title: String
    let tintColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(Color.white.opacity(isEnabled ? 0.08 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.08 : 0.05), lineWidth: 1)
            )
            .frame(height: ComposerLayout.flatActionButtonHeight)
            .overlay {
                HStack(spacing: 6) {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                    OverflowScrollingText(
                        text: title,
                        font: .system(size: 12, weight: .semibold, design: .rounded),
                        color: tintColor.opacity(isEnabled ? 1 : 0.42),
                        gap: 12,
                        speed: 22
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)
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

            OverflowScrollingText(
                text: title,
                font: .caption2.weight(.semibold),
                color: .white.opacity(0.88),
                gap: 14,
                speed: 24,
                expandsHorizontally: true
            )
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct ConversationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ConversationDetailPreviewContainer()
            .previewDisplayName("Conversation Detail")
    }
}
#endif
#endif
