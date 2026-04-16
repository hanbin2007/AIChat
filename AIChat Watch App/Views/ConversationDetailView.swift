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
    static let latestReplyStartAnchorID = "conversation-latest-reply-start-anchor"
    static let interruptionDragMinimumDistance: CGFloat = 6
    static let interruptionThreshold: CGFloat = 20
    static let autoScrollAnimationDuration: TimeInterval = 1.0
    static let suppressionDuration: TimeInterval = 1.05
    static let streamingRenderResumeDelayNanoseconds: UInt64 = 3_000_000_000
    static let streamingAutoScrollThrottleInterval: TimeInterval = 0.3

    static var autoScrollAnimation: Animation {
        .timingCurve(0.18, 0.92, 0.22, 1.0, duration: autoScrollAnimationDuration)
    }
}

private enum ConversationRendering {
    static let prewarmedRenderBudget = 10
    static let initialRenderBudget = 32
    static let olderRenderBudget = 64
    static let deferredRenderThreshold = 48
    static let initialLoadDelayNanoseconds: UInt64 = 120_000_000
}

/// Holds high-frequency scroll position values without triggering view invalidation.
private final class ScrollGeometryTracker {
    var viewportHeight: CGFloat = 0
    var distanceFromBottom: CGFloat = 0
}

struct ConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var isShowingToolSettings = false
    @State private var isShowingModelPicker = false
    @State private var isShowingThinkingPicker = false
    @State private var isComposerExpanded = true
    @State private var isShowingActivationCenter = false
    @State private var isAutoScrollInterrupted = false
    @State private var activeAutoScrollSessionMessageID: UUID?
    @State private var interruptedAutoScrollSessionMessageID: UUID?
    @State private var suspendedStreamingRenderMessageID: UUID?
    @State private var completedAutoScrollReplyMessageID: UUID?
    @State private var pendingHistoryAnchorMessageID: UUID?
    @State private var scrollInterruptionsSuppressedUntil = Date.distantPast
    /// Reference-type holder for scroll geometry values that update at high
    /// frequency (every scroll frame). Using @State here would trigger body
    /// re-evaluation on every frame — the reference wrapper avoids this since
    /// mutating properties on the class instance doesn't change the @State reference.
    @State private var scrollGeometry = ScrollGeometryTracker()
    @State private var voiceCaptureMode: VoiceCaptureMode = .transcribe
    @State private var suppressedVoiceTapUntil = Date.distantPast
    @State private var renderedMessageBudget = ConversationRendering.prewarmedRenderBudget
    @State private var lastObservedMessageCount = 0
    @State private var lastObservedHistoryCost = 0
    @State private var isPreparingHistory = true
    @State private var autoScrollInvocationCount = 0
    @State private var voiceRecorderNoticeMessage: String?
    @State private var toolSettingsDraft: ToolSettingsDraft?
    @State private var initialHistoryLoadTask: Task<Void, Never>?
    @State private var streamingRenderResumeTask: Task<Void, Never>?
    @State private var lastAutoScrollAt = Date.distantPast
    #if DEBUG
    @ObservedObject private var backgroundReplyDebugProbe = UITestBackgroundReplyDebugProbe.shared
    #endif

    var body: some View {
        ZStack {
            AppBackdropView()

            if let conversation = chatStore.conversation(id: conversationID) {
                VStack(spacing: ComposerLayout.messagesToComposerSpacing) {
                    messagesView(conversation: conversation)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    composerSurface
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .frame(height: isComposerExpanded ? nil : 0, alignment: .bottom)
                        .clipped()
                        .opacity(isComposerExpanded ? 1 : 0)
                        .allowsHitTesting(isComposerExpanded)
                        .accessibilityHidden(isComposerExpanded == false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 6)
                .padding(.bottom, ComposerLayout.containerBottomPadding)
                .overlay(alignment: .bottomTrailing) {
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
                .accessibilityIdentifier("conversation.settings.open")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ConversationSettingsView(conversationID: conversationID)
        }
        .sheet(isPresented: $isShowingToolSettings, onDismiss: commitToolSettingsDraft) {
            conversationToolSheet
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
        .onChange(of: voiceRecorder.noticeMessage) { _, noticeMessage in
            voiceRecorderNoticeMessage = noticeMessage
        }
        .onDisappear {
            initialHistoryLoadTask?.cancel()
            initialHistoryLoadTask = nil
            streamingRenderResumeTask?.cancel()
            streamingRenderResumeTask = nil
            chatStore.setStreamingFlushSuppressed(false)
        }
        .animation(.easeOut(duration: 0.2), value: isComposerExpanded)
    }

    @ViewBuilder
    private var composerSurface: some View {
        if chatStore.isReadOnlyMode {
            lockedComposerView
        } else {
            composerView()
        }
    }

    private func messagesView(conversation: ConversationThread) -> some View {
        let streamingMessageID = currentStreamingMessageID(in: conversation)
        let latestAssistantMessageID = latestAssistantMessageID(in: conversation.messages)
        let latestMessageID = conversation.messages.last?.id
        let autoScrollSessionMessageID = activeAutoScrollSessionMessageID ?? latestAssistantMessageID
        let visibleMessages = visibleMessages(in: conversation)
        let hiddenMessageCount = max(conversation.messages.count - visibleMessages.count, 0)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if conversation.messages.isEmpty {
                        starterCard
                    } else {
                        if isPreparingHistory {
                            historyLoadingCard(
                                visibleCount: visibleMessages.count,
                                totalCount: conversation.messages.count
                            )
                        } else if hiddenMessageCount > 0 {
                            loadEarlierMessagesCard(
                                hiddenMessageCount: hiddenMessageCount,
                                totalCount: conversation.messages.count
                            )
                        }

                        ForEach(visibleMessages) { message in
                            ChatBubbleView(
                                conversationID: conversationID,
                                message: message,
                                suspendStreamingRender: suspendedStreamingRenderMessageID == message.id,
                                forceExpandedContent: latestMessageID == message.id,
                                isLatestReplyAnchorTarget: latestMessageID == message.id && message.role == .assistant,
                                onPinMessage: { messageID, convoID, scope in
                                    await chatStore.pinMessage(id: messageID, from: convoID, scope: scope)
                                }
                            )
                                .equatable()
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

                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(maxWidth: .infinity)
                        .frame(height: isComposerExpanded ? ComposerLayout.expandedBottomInset : ComposerLayout.collapsedBottomInset)
                        .contentShape(Rectangle())
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
            .accessibilityIdentifier("conversation.messages.scroll")
            .coordinateSpace(name: ConversationScrollLayout.coordinateSpaceName)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ConversationViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .overlay(alignment: .topLeading) {
                if isAutoScrollUITestDiagnosticsEnabled {
                    autoScrollDebugProbe(
                        autoScrollSessionMessageID: autoScrollSessionMessageID,
                        streamingMessageID: streamingMessageID
                    )
                }
            }
            .overlay(alignment: .topTrailing) {
                #if DEBUG
                if isBackgroundReplyUITestDiagnosticsEnabled {
                    backgroundReplyDebugView(conversation: conversation)
                }
                #endif
            }
            .overlay(alignment: .bottomTrailing) {
                if chatStore.canRetryLatestReply(in: conversationID) {
                    retryButton
                        .padding(.trailing, 8)
                        .padding(.bottom, isComposerExpanded ? 12 : 62)
                }
            }

            .onPreferenceChange(ConversationViewportHeightPreferenceKey.self) { height in
                scrollGeometry.viewportHeight = height
            }
            .onPreferenceChange(ConversationBottomAnchorMaxYPreferenceKey.self) { maxY in
                handleBottomAnchorPositionChange(
                    maxY,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    streamingMessageID: streamingMessageID
                )
            }
            .onAppear {
                isComposerExpanded = preferredComposerExpansion(for: conversation)
                activeAutoScrollSessionMessageID = latestAssistantMessageID
                isAutoScrollInterrupted = false
                interruptedAutoScrollSessionMessageID = nil
                suspendedStreamingRenderMessageID = nil
                completedAutoScrollReplyMessageID = nil
                pendingHistoryAnchorMessageID = nil
                scrollGeometry.distanceFromBottom = 0
                autoScrollInvocationCount = 0
                streamingRenderResumeTask?.cancel()
                streamingRenderResumeTask = nil
                prepareInitialHistoryIfNeeded(messages: conversation.messages)
                scrollToAutoScrollTargetIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestAssistantMessageID: latestAssistantMessageID,
                    force: true
                )

                if shouldAutoCollapseComposerForTouchScrollUITest, isComposerExpanded {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard shouldAutoCollapseComposerForTouchScrollUITest else {
                            return
                        }

                        collapseComposer()
                    }
                } else if shouldAutoCollapseComposerForTouchScrollUITest {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard shouldAutoCollapseComposerForTouchScrollUITest else {
                            return
                        }

                        expandComposer()

                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard shouldAutoCollapseComposerForTouchScrollUITest else {
                            return
                        }

                        collapseComposer()
                    }
                }
            }
            .onChange(of: conversation.messages.count) { _, _ in
                reconcileRenderedHistory(with: conversation.messages)
                if conversation.messages.last?.role == .user {
                    completedAutoScrollReplyMessageID = nil
                }

                scrollToAutoScrollTargetIfNeeded(
                    with: proxy,
                    animated: true,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestAssistantMessageID: latestAssistantMessageID
                )
            }
            .onChange(of: renderedMessageBudget) { _, newBudget in
                guard newBudget > 0 else {
                    return
                }

                if let pendingHistoryAnchorMessageID {
                    scrollToMessage(
                        pendingHistoryAnchorMessageID,
                        with: proxy,
                        anchor: .top
                    )
                    self.pendingHistoryAnchorMessageID = nil
                    return
                }

                scrollToAutoScrollTargetIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestAssistantMessageID: latestAssistantMessageID
                )
            }
            .onChange(of: conversation.updatedAt) { _, _ in
                scrollToAutoScrollTargetIfNeeded(
                    with: proxy,
                    animated: true,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestAssistantMessageID: latestAssistantMessageID
                )
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _, isSending in
                if isSending {
                    completedAutoScrollReplyMessageID = nil
                }

                scrollToAutoScrollTargetIfNeeded(
                    with: proxy,
                    animated: true,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestAssistantMessageID: latestAssistantMessageID
                )
            }
            .onChange(of: chatStore.isGlobalAutoScrollEnabled) { _, isEnabled in
                if isEnabled {
                    isAutoScrollInterrupted = false
                    interruptedAutoScrollSessionMessageID = nil
                    scrollToAutoScrollTargetIfNeeded(
                        with: proxy,
                        animated: true,
                        autoScrollSessionMessageID: autoScrollSessionMessageID,
                        latestAssistantMessageID: latestAssistantMessageID,
                        force: true
                    )
                }
            }
            .onChange(of: streamingMessageID) { _, newMessageID in
                handleStreamingMessageChange(
                    newMessageID,
                    latestAssistantMessageID: latestAssistantMessageID,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    latestMessageID: latestMessageID,
                    with: proxy
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
                Button(readOnlyActivationEntryTitle) {
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

    private func historyLoadingCard(visibleCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.cyan)

            VStack(alignment: .leading, spacing: 3) {
                Text("正在准备历史消息")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)

                Text("先显示最近 \(visibleCount) / \(totalCount) 条。")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func loadEarlierMessagesCard(hiddenMessageCount: Int, totalCount: Int) -> some View {
        Button {
            loadOlderMessages(messages: chatStore.conversation(id: conversationID)?.messages ?? [])
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("加载更早消息")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("还有 \(hiddenMessageCount) 条未显示。")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func composerView() -> some View {
        let aiConfiguration = chatStore.aiConfiguration(for: conversationID)
        let attachments = chatStore.draftAttachments(for: conversationID)
        let draftText = chatStore.draftText(for: conversationID)
        let previousUserMessageText = chatStore.latestReusableUserMessageText(for: conversationID)
        let hasAttachments = attachments.isEmpty == false
        let hasDraftText = draftText.nonEmptyTrimmed != nil
        let hasDraftContent = hasDraftText || hasAttachments
        let isTranscribing = chatStore.isTranscribing(conversationID: conversationID)
        let isSendingReply = chatStore.isSending(conversationID: conversationID)
        let inputRowHeight = hasAttachments ? ComposerLayout.compactInputRowHeight : ComposerLayout.regularInputRowHeight
        let sendButtonSize = hasAttachments ? ComposerLayout.compactActionButtonSize : ComposerLayout.regularActionButtonSize
        let sendEnabled =
            isSendingReply == false &&
            isTranscribing == false &&
            voiceRecorder.isInteractive &&
            hasDraftContent
        let canRestorePreviousMessage =
            hasAttachments == false &&
            hasDraftText == false &&
            previousUserMessageText != nil &&
            isSendingReply == false &&
            isTranscribing == false &&
            voiceRecorder.isInteractive
        let primaryButtonSymbolName =
            isSendingReply ? "stop.fill" :
            (canRestorePreviousMessage ? "arrow.uturn.backward.circle.fill" : "arrow.up.circle.fill")
        let primaryButtonAccessibilityLabel =
            isSendingReply ? "Stop response" :
            (canRestorePreviousMessage ? L10n.tr("conversation.restore_previous_message") : "Send")
        let voiceButtonLabel =
            voiceRecorder.isRecording ?
            (voiceCaptureMode == .direct ? "Stop & Send" : "Stop & Transcribe") :
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

            if let voiceRecorderNoticeMessage {
                ConfigurationBannerView(
                    iconName: "waveform.badge.exclamationmark",
                    title: L10n.tr("notice.voice.fallback_title"),
                    message: voiceRecorderNoticeMessage
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
                    } else if canRestorePreviousMessage {
                        restorePreviousUserMessage()
                    } else {
                        sendCurrentDraft()
                    }
                } label: {
                    ComposerActionButtonLabel(
                        systemName: primaryButtonSymbolName,
                        dimension: sendButtonSize,
                        fillStyle: AnyShapeStyle(
                            isSendingReply ?
                                Color.red.opacity(0.94) :
                                Color.cyan.opacity((sendEnabled || canRestorePreviousMessage) ? 0.96 : 0.42)
                        ),
                        strokeColor: Color.white.opacity(
                            isSendingReply ?
                                0.16 :
                                ((sendEnabled || canRestorePreviousMessage) ? 0.10 : 0.05)
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: sendButtonSize,
                    height: sendButtonSize
                )
                .disabled(isSendingReply ? false : (sendEnabled || canRestorePreviousMessage) == false)
                .accessibilityLabel(primaryButtonAccessibilityLabel)
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
                    (voiceCaptureMode == .direct ? "Stop recording and send audio" : "Stop recording and transcribe") :
                    "Record voice message"
                )
                .accessibilityHint("Long press to send the recorded audio directly.")

                Button(action: presentToolSettings) {
                    ComposerToolButtonLabel(
                        symbolNames: toolButtonSymbols(for: aiConfiguration),
                        tintColor: toolButtonTint(for: aiConfiguration)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(voiceRecorder.isRecording || isTranscribing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(toolButtonAccessibilityLabel(for: aiConfiguration))
                .accessibilityValue(toolButtonAccessibilityValue(for: aiConfiguration))
                .accessibilityIdentifier("conversation.tool-entry")
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
        .contentShape(isComposerExpanded ? AnyShape(RoundedRectangle(cornerRadius: hasAttachments ? 20 : 22, style: .continuous)) : AnyShape(Rectangle().size(.zero)))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard isComposerExpanded else {
                        return
                    }

                    guard isPredominantlyVertical(value.translation) else {
                        return
                    }

                    if value.translation.height > 24 {
                        collapseComposer()
                    }
                }
        )
        .accessibilityIdentifier("conversation.composer")
    }

    private var lockedComposerView: some View {
        ActivationStatusCard(
            title: "发送已锁定",
            message: chatStore.activationStatusMessage,
            iconName: "lock.fill",
            accentColor: .orange,
            actionTitle: readOnlyActivationEntryTitle
        ) {
            isShowingActivationCenter = true
        }
        .accessibilityIdentifier("conversation.composer")
        .contentShape(isComposerExpanded ? AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous)) : AnyShape(Rectangle().size(.zero)))
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    guard isComposerExpanded else {
                        return
                    }

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
        .accessibilityIdentifier("conversation.composer.open")
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

    private var conversationToolSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("联网搜索", isOn: googleSearchEnabledBinding())
                        .accessibilityIdentifier("conversation.tool-search")
                    Toggle("运行代码", isOn: codeExecutionEnabledBinding())
                        .accessibilityIdentifier("conversation.tool-code")
                } footer: {
                    Text("是否可用取决于当前 Gemini 模型是否支持对应工具。")
                }

                Section("图片") {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 3,
                        matching: .images
                    ) {
                        Label("添加图片", systemImage: "photo.on.rectangle")
                    }
                    .disabled(voiceRecorder.isRecording || chatStore.isTranscribing(conversationID: conversationID))
                    .accessibilityIdentifier("conversation.tool-photo-picker")
                }

                Section {
                    Button("完成") {
                        isShowingToolSettings = false
                    }
                    .accessibilityIdentifier("conversation.tool-done")
                }
            }
            .accessibilityIdentifier("conversation.tool-sheet")
            .navigationTitle("工具与图片")
            .navigationBarTitleDisplayMode(.inline)
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
        isShowingToolSettings = false
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
        toggleVoiceRecording(startMode: .direct)
    }

    private func toggleVoiceRecording(startMode: VoiceCaptureMode) {
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
            return
        }

        voiceCaptureMode = startMode
        voiceRecorderNoticeMessage = nil
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
            case .direct:
                collapseComposer()
                await chatStore.sendRecordedAudioDirectly(attachment, in: conversationID)
            }
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        isAutoScrollInterrupted = false
        autoScrollInvocationCount += 1
        scrollInterruptionsSuppressedUntil = Date.now.addingTimeInterval(ConversationScrollLayout.suppressionDuration)
        lastAutoScrollAt = Date.now

        if animated {
            withAnimation(ConversationScrollLayout.autoScrollAnimation) {
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

    private func scrollToReplyStart(with proxy: ScrollViewProxy, animated: Bool) {
        isAutoScrollInterrupted = false
        autoScrollInvocationCount += 1
        scrollInterruptionsSuppressedUntil = Date.now.addingTimeInterval(ConversationScrollLayout.suppressionDuration)

        if animated {
            withAnimation(ConversationScrollLayout.autoScrollAnimation) {
                proxy.scrollTo(ConversationScrollLayout.latestReplyStartAnchorID, anchor: .top)
            }
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(ConversationScrollLayout.latestReplyStartAnchorID, anchor: .top)
        }
    }

    private func scrollToMessage(
        _ messageID: UUID,
        with proxy: ScrollViewProxy,
        anchor: UnitPoint
    ) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(messageID, anchor: anchor)
        }
    }

    private func currentStreamingMessageID(in conversation: ConversationThread) -> UUID? {
        conversation.messages.last(where: { $0.role == .assistant && $0.status == .streaming })?.id
    }

    private func scrollToAutoScrollTargetIfNeeded(
        with proxy: ScrollViewProxy,
        animated: Bool,
        autoScrollSessionMessageID: UUID?,
        latestAssistantMessageID: UUID?,
        force: Bool = false
    ) {
        guard force || shouldAutoScroll(for: autoScrollSessionMessageID) else {
            return
        }

        if force == false,
           Date.now.timeIntervalSince(lastAutoScrollAt) < ConversationScrollLayout.streamingAutoScrollThrottleInterval {
            return
        }

        if let completedAutoScrollReplyMessageID,
           completedAutoScrollReplyMessageID == latestAssistantMessageID {
            scrollToReplyStart(with: proxy, animated: animated)
            return
        }

        scrollToBottom(with: proxy, animated: animated)
    }

    private func shouldAutoScroll(for autoScrollSessionMessageID: UUID?) -> Bool {
        guard chatStore.isGlobalAutoScrollEnabled else {
            return false
        }

        if interruptedAutoScrollSessionMessageID == autoScrollSessionMessageID,
           interruptedAutoScrollSessionMessageID != nil {
            return false
        }

        return isAutoScrollInterrupted == false
    }

    private func handleStreamingMessageChange(
        _ streamingMessageID: UUID?,
        latestAssistantMessageID: UUID?,
        autoScrollSessionMessageID: UUID?,
        latestMessageID: UUID?,
        with proxy: ScrollViewProxy
    ) {
        if let streamingMessageID {
            activeAutoScrollSessionMessageID = streamingMessageID
            completedAutoScrollReplyMessageID = nil

            if interruptedAutoScrollSessionMessageID != nil,
               interruptedAutoScrollSessionMessageID != streamingMessageID {
                interruptedAutoScrollSessionMessageID = nil
                isAutoScrollInterrupted = false
            }

            suspendedStreamingRenderMessageID = nil
            streamingRenderResumeTask?.cancel()
            streamingRenderResumeTask = nil
            chatStore.setStreamingFlushSuppressed(false)
            scrollToAutoScrollTargetIfNeeded(
                with: proxy,
                animated: true,
                autoScrollSessionMessageID: autoScrollSessionMessageID,
                latestAssistantMessageID: latestAssistantMessageID
            )
            return
        }

        if let latestAssistantMessageID {
            activeAutoScrollSessionMessageID = latestAssistantMessageID
        }

        if latestAssistantMessageID == latestMessageID {
            completedAutoScrollReplyMessageID = latestAssistantMessageID
        } else {
            completedAutoScrollReplyMessageID = nil
        }

        suspendedStreamingRenderMessageID = nil
        streamingRenderResumeTask?.cancel()
        streamingRenderResumeTask = nil
        chatStore.setStreamingFlushSuppressed(false)
        scrollToAutoScrollTargetIfNeeded(
            with: proxy,
            animated: true,
            autoScrollSessionMessageID: autoScrollSessionMessageID,
            latestAssistantMessageID: latestAssistantMessageID
        )
    }

    private func interruptAutoScroll(for autoScrollSessionMessageID: UUID?) {
        isAutoScrollInterrupted = true

        if let autoScrollSessionMessageID {
            interruptedAutoScrollSessionMessageID = autoScrollSessionMessageID
        }
    }

    private func interruptAutoScrollImmediately(for autoScrollSessionMessageID: UUID?) {
        guard shouldAutoScroll(for: autoScrollSessionMessageID) else {
            return
        }

        scrollInterruptionsSuppressedUntil = .distantPast
        interruptAutoScroll(for: autoScrollSessionMessageID)
    }

    private func pauseStreamingRefresh(
        for streamingMessageID: UUID?,
        autoScrollSessionMessageID: UUID?
    ) {
        interruptAutoScrollImmediately(for: autoScrollSessionMessageID)
        suspendStreamingRender(for: streamingMessageID)
    }

    private func suspendStreamingRender(for streamingMessageID: UUID?) {
        guard let streamingMessageID else {
            return
        }

        suspendedStreamingRenderMessageID = streamingMessageID
        chatStore.setStreamingFlushSuppressed(true)
        scheduleStreamingRenderResume(for: streamingMessageID)
    }

    private func scheduleStreamingRenderResume(for streamingMessageID: UUID) {
        streamingRenderResumeTask?.cancel()
        streamingRenderResumeTask = Task {
            try? await Task.sleep(nanoseconds: ConversationScrollLayout.streamingRenderResumeDelayNanoseconds)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                guard suspendedStreamingRenderMessageID == streamingMessageID else {
                    return
                }

                suspendedStreamingRenderMessageID = nil
                streamingRenderResumeTask = nil
                chatStore.setStreamingFlushSuppressed(false)
            }
        }
    }

    private func handleBottomAnchorPositionChange(
        _ maxY: CGFloat,
        autoScrollSessionMessageID: UUID?,
        streamingMessageID: UUID? = nil
    ) {
        guard scrollGeometry.viewportHeight > 0 else {
            return
        }

        let distanceFromBottom = maxY - scrollGeometry.viewportHeight
        let previousDistance = scrollGeometry.distanceFromBottom
        scrollGeometry.distanceFromBottom = max(distanceFromBottom, 0)

        // Detect user scrolling away from bottom even during the suppression
        // window — replaces the removed DragGesture's pauseStreamingRefresh.
        if distanceFromBottom > ConversationScrollLayout.interruptionThreshold,
           distanceFromBottom > previousDistance + 4 {
            suspendStreamingRender(for: streamingMessageID)
        }

        // Auto-scroll interruption is subject to the suppression window to avoid
        // false positives from programmatic scroll animations.
        guard Date.now >= scrollInterruptionsSuppressedUntil else {
            return
        }

        if completedAutoScrollReplyMessageID == autoScrollSessionMessageID,
           completedAutoScrollReplyMessageID != nil {
            return
        }

        guard distanceFromBottom > ConversationScrollLayout.interruptionThreshold else {
            guard interruptedAutoScrollSessionMessageID != autoScrollSessionMessageID else {
                return
            }

            isAutoScrollInterrupted = false
            return
        }

        interruptAutoScroll(for: autoScrollSessionMessageID)
    }

    private func visibleMessages(in conversation: ConversationThread) -> ArraySlice<ChatMessage> {
        guard conversation.messages.isEmpty == false else {
            return conversation.messages.suffix(0)
        }

        if lastObservedMessageCount == conversation.messages.count,
           renderedMessageBudget >= lastObservedHistoryCost {
            return conversation.messages.suffix(conversation.messages.count)
        }

        let visibleCount = ConversationHistoryRenderBudget.visibleMessageCount(
            in: conversation.messages,
            budget: renderedMessageBudget
        )
        return conversation.messages.suffix(visibleCount)
    }

    private func prepareInitialHistoryIfNeeded(messages: [ChatMessage]) {
        initialHistoryLoadTask?.cancel()
        let totalCount = messages.count
        let totalHistoryCost = ConversationHistoryRenderBudget.totalCost(in: messages)

        lastObservedMessageCount = totalCount
        lastObservedHistoryCost = totalHistoryCost
        renderedMessageBudget = ConversationRendering.prewarmedRenderBudget

        guard ConversationHistoryRenderBudget.shouldDeferInitialRendering(
            in: messages,
            threshold: ConversationRendering.deferredRenderThreshold
        ) else {
            renderedMessageBudget = totalHistoryCost
            isPreparingHistory = false
            return
        }

        isPreparingHistory = true
        initialHistoryLoadTask = Task {
            try? await Task.sleep(nanoseconds: ConversationRendering.initialLoadDelayNanoseconds)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                renderedMessageBudget = min(
                    lastObservedHistoryCost,
                    ConversationRendering.initialRenderBudget
                )
                isPreparingHistory = false
                initialHistoryLoadTask = nil
            }
        }
    }

    private func reconcileRenderedHistory(with messages: [ChatMessage]) {
        let totalCount = messages.count
        let totalHistoryCost = ConversationHistoryRenderBudget.totalCost(in: messages)
        let previousCount = lastObservedMessageCount
        let previousHistoryCost = lastObservedHistoryCost

        lastObservedMessageCount = totalCount
        lastObservedHistoryCost = totalHistoryCost

        guard previousCount != totalCount || previousHistoryCost != totalHistoryCost else {
            return
        }

        if ConversationHistoryRenderBudget.shouldDeferInitialRendering(
            in: messages,
            threshold: ConversationRendering.deferredRenderThreshold
        ) == false {
            renderedMessageBudget = totalHistoryCost
            isPreparingHistory = false
            return
        }

        if totalCount < previousCount || totalHistoryCost < previousHistoryCost {
            renderedMessageBudget = min(renderedMessageBudget, totalHistoryCost)
            return
        }

        let deltaHistoryCost = totalHistoryCost - previousHistoryCost
        let wasShowingAll = renderedMessageBudget >= previousHistoryCost

        if isPreparingHistory {
            renderedMessageBudget = min(
                totalHistoryCost,
                max(
                    renderedMessageBudget + deltaHistoryCost,
                    ConversationRendering.prewarmedRenderBudget
                )
            )
            return
        }

        if wasShowingAll {
            renderedMessageBudget = totalHistoryCost
        } else {
            renderedMessageBudget = min(totalHistoryCost, renderedMessageBudget + deltaHistoryCost)
        }
    }

    private func loadOlderMessages(messages: [ChatMessage]) {
        guard messages.isEmpty == false else {
            return
        }

        interruptAutoScroll(for: activeAutoScrollSessionMessageID ?? latestAssistantMessageID(in: messages))
        pendingHistoryAnchorMessageID = ConversationHistoryRenderBudget.lastHiddenMessageID(
            in: messages,
            budget: renderedMessageBudget
        )

        renderedMessageBudget = ConversationHistoryRenderBudget.budgetForLoadingOlderMessages(
            in: messages,
            currentBudget: max(
                renderedMessageBudget,
                ConversationRendering.initialRenderBudget
            ),
            preferredIncrement: ConversationRendering.olderRenderBudget
        )
    }

    private func preferredComposerExpansion(for conversation: ConversationThread) -> Bool {
        let hasDraftContent =
            chatStore.draftText(for: conversationID).nonEmptyTrimmed != nil ||
            chatStore.draftAttachments(for: conversationID).isEmpty == false
        let isBusy =
            chatStore.isSending(conversationID: conversationID) ||
            chatStore.isTranscribing(conversationID: conversationID)

        if hasDraftContent || isBusy || conversation.messages.isEmpty {
            return true
        }

        return conversation.messages.count < 6
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

    private func restorePreviousUserMessage() {
        guard chatStore.restoreLatestUserMessageToDraft(for: conversationID) else {
            return
        }

        chatStore.clearError(for: conversationID)
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

    private var isAutoScrollUITestDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment["AIChat_UI_TEST_SCENARIO"] == "conversation_autoscroll_interrupt"
    }

    private var shouldAutoCollapseComposerForTouchScrollUITest: Bool {
        ProcessInfo.processInfo.environment["AIChat_UI_TEST_SCENARIO"] == "conversation_touch_scroll_after_collapse"
    }

    #if DEBUG
    private var isBackgroundReplyUITestDiagnosticsEnabled: Bool {
        ProcessInfo.processInfo.environment["AIChat_UI_TEST_SCENARIO"] == "conversation_background_reply_notification"
    }
    #endif

    private func latestAssistantMessageID(in messages: [ChatMessage]) -> UUID? {
        messages.last(where: { $0.role == .assistant })?.id
    }

    private func autoScrollDebugLabel(
        autoScrollSessionMessageID: UUID?,
        streamingMessageID: UUID?
    ) -> String {
        [
            "session=\(autoScrollSessionMessageID?.uuidString ?? "nil")",
            "locked=\(interruptedAutoScrollSessionMessageID?.uuidString ?? "nil")",
            "interrupted=\(isAutoScrollInterrupted ? 1 : 0)",
            "streaming=\(streamingMessageID?.uuidString ?? "nil")",
            "distance=\(Int(scrollGeometry.distanceFromBottom.rounded()))",
            "count=\(autoScrollInvocationCount)"
        ].joined(separator: ";")
    }

    private func autoScrollDebugProbe(
        autoScrollSessionMessageID: UUID?,
        streamingMessageID: UUID?
    ) -> some View {
        Text(
            autoScrollDebugLabel(
                autoScrollSessionMessageID: autoScrollSessionMessageID,
                streamingMessageID: streamingMessageID
            )
        )
        .font(.system(size: 1))
        .foregroundStyle(.clear)
        .frame(width: 1, height: 1)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityIdentifier("conversation.scroll.debug")
    }

    #if DEBUG
    private func backgroundReplyDebugLabel(conversation: ConversationThread) -> String {
        let latestAssistantMessage = conversation.messages.last(where: { $0.role == .assistant })
        let isStreaming = latestAssistantMessage?.status == .streaming
        let hasVisibleReply = latestAssistantMessage?.hasVisibleContent ?? false

        return [
            "completed=\(backgroundReplyDebugProbe.completedEventCount)",
            "background=\(backgroundReplyDebugProbe.completedInBackgroundCount)",
            "event=\(backgroundReplyDebugProbe.lastEventIdentifier)",
            "streaming=\(isStreaming ? 1 : 0)",
            "status=\(latestAssistantMessage?.status.rawValue ?? "nil")",
            "visible=\(hasVisibleReply ? 1 : 0)"
        ].joined(separator: ";")
    }

    private func backgroundReplyDebugView(conversation: ConversationThread) -> some View {
        Text(backgroundReplyDebugLabel(conversation: conversation))
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityIdentifier("conversation.background_reply.debug")
    }
    #endif

    private func recordingStatusTitle() -> String {
        let duration = L10n.format("conversation.recording", voiceRecorder.elapsedTimeText)
        guard voiceCaptureMode == .direct else {
            return duration
        }

        return "Send Voice | \(duration)"
    }

    private var readOnlyActivationEntryTitle: String {
        if chatStore.configuration.backendMode == .relay,
           chatStore.hasManagedRelayAccess == false {
            return "申请使用"
        }

        return "输入激活码"
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

    private func googleSearchEnabledBinding() -> Binding<Bool> {
        Binding(
            get: {
                toolSettingsDraft?.usesGoogleSearch ??
                    chatStore.aiConfiguration(for: conversationID).usesGoogleSearch
            },
            set: { newValue in
                ensureToolSettingsDraft()
                toolSettingsDraft?.usesGoogleSearch = newValue
            }
        )
    }

    private func codeExecutionEnabledBinding() -> Binding<Bool> {
        Binding(
            get: {
                toolSettingsDraft?.usesCodeExecution ??
                    chatStore.aiConfiguration(for: conversationID).usesCodeExecution
            },
            set: { newValue in
                ensureToolSettingsDraft()
                toolSettingsDraft?.usesCodeExecution = newValue
            }
        )
    }

    private func presentToolSettings() {
        toolSettingsDraft = currentToolSettingsDraft()
        isShowingToolSettings = true
    }

    private func ensureToolSettingsDraft() {
        if toolSettingsDraft == nil {
            toolSettingsDraft = currentToolSettingsDraft()
        }
    }

    private func currentToolSettingsDraft() -> ToolSettingsDraft {
        let configuration = chatStore.aiConfiguration(for: conversationID)
        return ToolSettingsDraft(
            usesGoogleSearch: configuration.usesGoogleSearch,
            usesCodeExecution: configuration.usesCodeExecution
        )
    }

    private func commitToolSettingsDraft() {
        guard let draft = toolSettingsDraft else {
            return
        }

        toolSettingsDraft = nil

        let currentConfiguration = chatStore.aiConfiguration(for: conversationID)
        guard currentConfiguration.usesGoogleSearch != draft.usesGoogleSearch ||
                currentConfiguration.usesCodeExecution != draft.usesCodeExecution
        else {
            return
        }

        chatStore.setToolPreferences(
            usesGoogleSearch: draft.usesGoogleSearch,
            usesCodeExecution: draft.usesCodeExecution,
            for: conversationID
        )
    }

    private func toolButtonSymbols(for configuration: ConversationAIConfiguration) -> [String] {
        var symbols: [String] = []

        if configuration.usesGoogleSearch {
            symbols.append("globe")
        }

        if configuration.usesCodeExecution {
            symbols.append("chevron.left.forwardslash.chevron.right")
        }

        if symbols.isEmpty {
            symbols.append("photo.on.rectangle")
        }

        return symbols
    }

    private func toolButtonTint(for configuration: ConversationAIConfiguration) -> Color {
        (configuration.usesGoogleSearch || configuration.usesCodeExecution) ? .cyan : .white
    }

    private func toolButtonAccessibilityLabel(for configuration: ConversationAIConfiguration) -> String {
        let enabledFeatures = [
            configuration.usesGoogleSearch ? "联网搜索" : nil,
            configuration.usesCodeExecution ? "运行代码" : nil
        ].compactMap { $0 }

        guard enabledFeatures.isEmpty == false else {
            return "工具与图片"
        }

        return "工具与图片，已启用\(enabledFeatures.joined(separator: "、"))"
    }

    private func toolButtonAccessibilityValue(for configuration: ConversationAIConfiguration) -> String {
        let enabledFeatures = [
            configuration.usesGoogleSearch ? "联网搜索" : nil,
            configuration.usesCodeExecution ? "运行代码" : nil
        ].compactMap { $0 }

        guard enabledFeatures.isEmpty == false else {
            return "未启用附加工具"
        }

        return enabledFeatures.joined(separator: "、")
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

            Text(title)
                .font(.system(size: titlePointSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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

private struct ComposerToolButtonLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let symbolNames: [String]
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
                HStack(spacing: 5) {
                    ForEach(symbolNames, id: \.self) { symbolName in
                        Image(systemName: symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tintColor.opacity(isEnabled ? 1 : 0.42))
                    }
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

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    private var formattedDuration: String? {
        guard let durationSeconds = attachment.durationSeconds, durationSeconds > 0 else {
            return nil
        }

        return Self.durationFormatter.string(from: durationSeconds)
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
