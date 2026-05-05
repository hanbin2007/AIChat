#if COMPANION_APP
//
//  CompanionConversationDetailView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import PhotosUI
import SwiftUI

private enum CompanionConversationScrollLayout {
    static let coordinateSpaceName = "companion-conversation-scroll"
    static let interruptionDragMinimumDistance: CGFloat = 12
    static let interruptionThreshold: CGFloat = 32
    static let suppressionDuration: TimeInterval = 0.28
    static let streamingRenderResumeDelayNanoseconds: UInt64 = 3_000_000_000
}

private enum CompanionVoiceCaptureMode {
    case transcribe
    case directSend
}

private enum CompanionConversationRendering {
    static let prewarmedRenderBudget = 12
    static let initialRenderBudget = 40
    static let olderRenderBudget = 80
    static let deferredRenderThreshold = 60
    static let initialLoadDelayNanoseconds: UInt64 = 120_000_000
}

private struct CompanionToolSettingsDraft: Equatable {
    var usesGoogleSearch: Bool
    var usesCodeExecution: Bool
}

struct CompanionConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var isShowingToolSettings = false
    @State private var isShowingActivationCenter = false
    @State private var isAutoScrollInterrupted = false
    @State private var activeAutoScrollSessionMessageID: UUID?
    @State private var interruptedAutoScrollSessionMessageID: UUID?
    @State private var suspendedStreamingRenderMessageID: UUID?
    @State private var pendingHistoryAnchorMessageID: UUID?
    @State private var scrollInterruptionsSuppressedUntil = Date.distantPast
    @State private var messagesViewportHeight: CGFloat = 0
    @State private var voiceCaptureMode: CompanionVoiceCaptureMode = .transcribe
    @State private var suppressedVoiceTapUntil = Date.distantPast
    @FocusState private var isDraftFieldFocused: Bool
    @State private var renderedMessageBudget = CompanionConversationRendering.prewarmedRenderBudget
    @State private var lastObservedMessageCount = 0
    @State private var lastObservedHistoryCost = 0
    @State private var isPreparingHistory = true
    @State private var toolSettingsDraft: CompanionToolSettingsDraft?
    @State private var initialHistoryLoadTask: Task<Void, Never>?
    @State private var streamingRenderResumeTask: Task<Void, Never>?
    /// Width of the composer's action row, sampled via PreferenceKey so the
    /// voice button can collapse into the TextField on narrow screens
    /// (iPhone mini / landscape <380pt). Zero until first layout.
    @State private var composerMeasuredWidth: CGFloat = 0

    private let bottomAnchorID = "conversation-bottom-anchor"

    var body: some View {
        ZStack {
            AppBackdropView()

            if let conversation = chatStore.conversation(id: conversationID) {
                conversationContent(conversation)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("这个会话已经不存在了")
                        .font(.headline)
                }
                .padding(24)
                .accessibilityIdentifier("companion.conversation.not-found")
            }
        }
        .navigationTitle(chatStore.conversation(id: conversationID)?.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("会话设置")
                .accessibilityIdentifier("conversation.settings.open")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            CompanionConversationSettingsView(conversationID: conversationID)
        }
        .sheet(isPresented: $isShowingToolSettings, onDismiss: commitToolSettingsDraft) {
            conversationToolSheet
        }
        .sheet(isPresented: $isShowingActivationCenter) {
            CompanionActivationCenterView()
        }
        .onChange(of: selectedPhotoItems) { items in
            Task {
                await importPickedItems(items)
            }
        }
        .onChange(of: voiceRecorder.completedAttachment) { attachment in
            guard let attachment else {
                return
            }

            handleRecordedAttachment(attachment)
        }
        .onChange(of: voiceRecorder.errorMessage) { errorMessage in
            guard let errorMessage else {
                return
            }

            chatStore.presentError(errorMessage, for: conversationID)
            voiceRecorder.clearError()
        }
        .onDisappear {
            initialHistoryLoadTask?.cancel()
            initialHistoryLoadTask = nil
            streamingRenderResumeTask?.cancel()
            streamingRenderResumeTask = nil
        }
        .accessibilityIdentifier("companion.conversation.detail")
    }

    private func conversationContent(_ conversation: ConversationThread) -> some View {
        let streamingMessageID = currentStreamingMessageID(in: conversation)
        let latestAssistantMessageID = latestAssistantMessageID(in: conversation.messages)
        let latestMessageID = conversation.messages.last?.id
        let autoScrollSessionMessageID = activeAutoScrollSessionMessageID ?? latestAssistantMessageID
        let visibleMessages = visibleMessages(in: conversation)
        let hiddenMessageCount = max(conversation.messages.count - visibleMessages.count, 0)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    conversationHeaderCard(conversation: conversation)

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
                                visibleCount: visibleMessages.count,
                                totalCount: conversation.messages.count
                            )
                        }

                        ForEach(visibleMessages) { message in
                            ChatBubbleView(
                                conversationID: conversationID,
                                message: message,
                                suspendStreamingRender: suspendedStreamingRenderMessageID == message.id,
                                forceExpandedContent: latestMessageID == message.id,
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
                            title: "发送失败",
                            message: errorMessage
                        )
                        .id("conversation-error")
                    }

                    Color.clear
                        .frame(height: 6)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: CompanionConversationBottomAnchorMaxYPreferenceKey.self,
                                    value: geometry.frame(in: .named(CompanionConversationScrollLayout.coordinateSpaceName)).maxY
                                )
                            }
                        )
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: CompanionConversationScrollLayout.coordinateSpaceName)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: CompanionConversationViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerSurface
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: CompanionBottomSurfaceHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: CompanionConversationScrollLayout.interruptionDragMinimumDistance)
                    .onChanged { value in
                        guard abs(value.translation.height) >= CompanionConversationScrollLayout.interruptionDragMinimumDistance,
                              isPredominantlyVertical(value.translation)
                        else {
                            return
                        }

                        pauseStreamingRefresh(
                            for: streamingMessageID,
                            autoScrollSessionMessageID: autoScrollSessionMessageID
                        )
                    }
            )
            .onPreferenceChange(CompanionConversationViewportHeightPreferenceKey.self) { height in
                messagesViewportHeight = height
            }
            .onPreferenceChange(CompanionConversationBottomAnchorMaxYPreferenceKey.self) { maxY in
                handleBottomAnchorPositionChange(
                    maxY,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onAppear {
                activeAutoScrollSessionMessageID = latestAssistantMessageID
                isAutoScrollInterrupted = false
                interruptedAutoScrollSessionMessageID = nil
                suspendedStreamingRenderMessageID = nil
                pendingHistoryAnchorMessageID = nil
                streamingRenderResumeTask?.cancel()
                streamingRenderResumeTask = nil
                prepareInitialHistoryIfNeeded(messages: conversation.messages)
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    force: true
                )
            }
            .onChange(of: conversation.messages.count) { _ in
                reconcileRenderedHistory(with: conversation.messages)
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: true,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: renderedMessageBudget) { newBudget in
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

                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: conversation.updatedAt) { _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: streamingMessageID) { newMessageID in
                handleStreamingMessageChange(
                    newMessageID,
                    latestAssistantMessageID: latestAssistantMessageID,
                    autoScrollSessionMessageID: autoScrollSessionMessageID,
                    with: proxy
                )
            }
        }
    }

    private func conversationHeaderCard(conversation: ConversationThread) -> some View {
        let configuration = chatStore.aiConfiguration(for: conversation.id)

        return VStack(alignment: .leading, spacing: 14) {
            Text(conversation.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("继续这条会话，和手表实时同步。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 10) {
                CompanionHeaderMetric(title: "模型", value: AIModelCatalog.shortLabel(for: configuration.model))
                CompanionHeaderMetric(title: "Thinking", value: configuration.thinkingIntensity.shortLabel)
                CompanionHeaderMetric(title: "同步", value: chatStore.syncStatusDescription)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.18, blue: 0.24),
                            Color.black.opacity(0.42)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chatStore.isReadOnlyMode ? "当前设备只读" : "继续对话")
                .font(.headline)
                .foregroundStyle(.white)

            Text(
                chatStore.isReadOnlyMode ?
                "先看同步历史；激活后再继续发消息。" :
                "直接输入、录音，或加图片。"
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.78))

            if chatStore.isReadOnlyMode {
                Button("激活当前设备") {
                    isShowingActivationCenter = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                HStack(spacing: 10) {
                    starterChip("总结刚才的对话")
                    starterChip("分析这张图片")
                    starterChip("继续上一轮思路")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.36))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func starterChip(_ text: String) -> some View {
        Button(text) {
            chatStore.updateDraftText(text, for: conversationID)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.9))
    }

    private func historyLoadingCard(visibleCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                Text("正在准备历史消息")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("先显示最近 \(visibleCount) / \(totalCount) 条，等导航稳定后再继续。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func loadEarlierMessagesCard(
        hiddenMessageCount: Int,
        visibleCount: Int,
        totalCount: Int
    ) -> some View {
        Button {
            loadOlderMessages(messages: chatStore.conversation(id: conversationID)?.messages ?? [])
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("加载更早消息")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("还有 \(hiddenMessageCount) 条未渲染，当前显示最近 \(visibleCount) / \(totalCount) 条。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                Label("继续加载", systemImage: "arrow.up.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.30))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var composerSurface: some View {
        if chatStore.isReadOnlyMode {
            VStack(spacing: 0) {
                ActivationStatusCard(
                    title: "发送已锁定",
                    message: chatStore.activationStatusMessage,
                    iconName: "lock.fill",
                    accentColor: .orange,
                    actionTitle: "输入激活码"
                ) {
                    isShowingActivationCenter = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .background(companionComposerBackground.ignoresSafeArea(.container, edges: .bottom))
        } else {
            composerView
        }
    }

    private var composerView: some View {
        let aiConfiguration = chatStore.aiConfiguration(for: conversationID)
        let attachments = chatStore.draftAttachments(for: conversationID)
        let draftText = chatStore.draftText(for: conversationID)
        let previousUserMessageText = chatStore.latestReusableUserMessageText(for: conversationID)
        let hasDraftText = draftText.nonEmptyTrimmed != nil
        let hasDraftContent = hasDraftText || attachments.isEmpty == false
        let isTranscribing = chatStore.isTranscribing(conversationID: conversationID)
        let isSending = chatStore.isSending(conversationID: conversationID)
        let sendEnabled = hasDraftContent && isSending == false && isTranscribing == false && voiceRecorder.isInteractive
        let canRestorePreviousMessage =
            attachments.isEmpty &&
            hasDraftText == false &&
            previousUserMessageText != nil &&
            isSending == false &&
            isTranscribing == false &&
            voiceRecorder.isInteractive
        let voiceButtonDisabled =
            voiceRecorder.isRecording == false &&
            (isSending || isTranscribing || voiceRecorder.isPreparing)

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(chatStore.availableModelOptions()) { option in
                            Button(option.title) {
                                Task {
                                    await chatStore.updateModel(option.id, for: conversationID)
                                }
                            }
                        }
                    } label: {
                        CompanionComposerMenuLabel(
                            iconName: "cpu",
                            title: AIModelCatalog.shortLabel(for: aiConfiguration.model)
                        )
                    }

                    Menu {
                        ForEach(chatStore.availableThinkingIntensities(for: conversationID)) { intensity in
                            Button(intensity.displayName) {
                                Task {
                                    await chatStore.updateThinkingIntensity(intensity, for: conversationID)
                                }
                            }
                        }
                    } label: {
                        CompanionComposerMenuLabel(
                            iconName: "brain.head.profile",
                            title: aiConfiguration.thinkingIntensity.displayName
                        )
                    }
                }

                if attachments.isEmpty == false {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments) { attachment in
                                CompanionDraftAttachmentCard(
                                    attachment: attachment,
                                    onRemove: {
                                        chatStore.removeAttachment(id: attachment.id, from: conversationID)
                                    }
                                )
                            }
                        }
                    }
                }

                if voiceRecorder.isRecording || voiceRecorder.isPreparing {
                    CompanionInlineStatus(
                        iconName: voiceRecorder.isRecording ? "waveform.circle.fill" : "mic.circle",
                        title: voiceRecorder.isRecording ?
                            recordingStatusTitle() :
                            L10n.tr("conversation.microphone.preparing.zh")
                    )
                } else if isTranscribing {
                    CompanionInlineStatus(
                        iconName: "waveform.and.magnifyingglass",
                        title: L10n.format(
                            "conversation.transcribing.zh",
                            AITranscriptionModelCatalog.shortLabel(for: chatStore.selectedTranscriptionModel)
                        )
                    )
                }

                composerInputRow(
                    aiConfiguration: aiConfiguration,
                    voiceButtonDisabled: voiceButtonDisabled,
                    sendEnabled: sendEnabled,
                    canRestorePreviousMessage: canRestorePreviousMessage,
                    isTranscribing: isTranscribing
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(companionComposerBackground.ignoresSafeArea(.container, edges: .bottom))
        }
    }

    private var companionComposerBackground: some View {
        Rectangle()
            .fill(Color.black.opacity(0.78))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
    }

    /// Composer input row: TextField with an inline tool-entry "+" plus a
    /// circular voice and send button. On narrow screens (~iPhone mini /
    /// landscape <380pt) the voice button collapses into the TextField's
    /// trailing accessory area so the send button still has full breathing
    /// room. Replaces the previous three equal-width labelled buttons that
    /// drowned the primary "send" action and forced excessive composer
    /// height (issue #31).
    @ViewBuilder
    private func composerInputRow(
        aiConfiguration: ConversationAIConfiguration,
        voiceButtonDisabled: Bool,
        sendEnabled: Bool,
        canRestorePreviousMessage: Bool,
        isTranscribing: Bool
    ) -> some View {
        let isNarrow = composerMeasuredWidth > 0 && composerMeasuredWidth < 380
        let toolsDisabled = voiceRecorder.isRecording || isTranscribing

        HStack(alignment: .bottom, spacing: 8) {
            // TextField "pill" with always-visible tool entry, plus voice on
            // narrow screens.
            HStack(alignment: .bottom, spacing: 6) {
                TextField("Ask Gemini", text: draftTextBinding(), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .tint(.cyan)
                    .focused($isDraftFieldFocused)
                    .disabled(voiceRecorder.isRecording || isTranscribing)
                    .frame(maxWidth: .infinity, alignment: .leading)

                composerToolButton(aiConfiguration: aiConfiguration, disabled: toolsDisabled)

                if isNarrow {
                    composerVoiceButton(
                        disabled: voiceButtonDisabled,
                        compact: true
                    )
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            if isNarrow == false {
                composerVoiceButton(
                    disabled: voiceButtonDisabled,
                    compact: false
                )
            }

            composerSendButton(
                sendEnabled: sendEnabled,
                canRestorePreviousMessage: canRestorePreviousMessage
            )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: CompanionComposerWidthKey.self,
                        value: proxy.size.width
                    )
            }
        )
        .onPreferenceChange(CompanionComposerWidthKey.self) { width in
            composerMeasuredWidth = width
        }
    }

    // NOTE on accessibility patterns below: builds #44 and #47 both showed
    // that `Button(action:) { Image(...) }.buttonStyle(.plain)` with an
    // icon-only label drops the `accessibilityIdentifier` on iOS 26's
    // a11y bridge — XCUITest's `descendants(matching: .any)[<id>]` query
    // returns no match. Even adding `.accessibilityAddTraits(.isButton)`
    // didn't surface them. Replacing the Button with an `Image` plus a
    // tap-gesture and explicit `.isButton` trait keeps the visual exactly
    // the same, sidesteps the Button bridge entirely, and makes the
    // identifier reliably findable.
    @ViewBuilder
    private func composerToolButton(
        aiConfiguration: ConversationAIConfiguration,
        disabled: Bool
    ) -> some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 26, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(toolButtonTint(for: aiConfiguration))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.4 : 1.0)
            .onTapGesture {
                guard disabled == false else { return }
                presentToolSettings()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(toolButtonAccessibilityLabel(for: aiConfiguration))
            .accessibilityValue(toolButtonAccessibilityValue(for: aiConfiguration))
            .accessibilityIdentifier("conversation.tool-entry")
    }

    @ViewBuilder
    private func composerVoiceButton(disabled: Bool, compact: Bool) -> some View {
        let isRecording = voiceRecorder.isRecording
        let iconName = isRecording ? "stop.fill" : "waveform.badge.mic"
        let label =
            isRecording ?
            (voiceCaptureMode == .directSend ? "停止并发送" : "停止并转录") :
            "开始录音"
        let dimension: CGFloat = compact ? 36 : 44

        ZStack {
            Circle()
                .fill(isRecording ? Color.red.opacity(0.85) : Color.white.opacity(0.08))
            Image(systemName: iconName)
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: dimension, height: dimension)
        .contentShape(Circle())
        .opacity(disabled ? 0.4 : 1.0)
        .onTapGesture {
            guard disabled == false else { return }
            handleVoiceButtonTap()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard disabled == false else { return }
                    handleVoiceButtonLongPress()
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier("conversation.voice-button")
    }

    @ViewBuilder
    private func composerSendButton(
        sendEnabled: Bool,
        canRestorePreviousMessage: Bool
    ) -> some View {
        let iconName = canRestorePreviousMessage ?
            "arrow.uturn.backward.circle.fill" :
            "arrow.up.circle.fill"
        let label = canRestorePreviousMessage ?
            L10n.tr("conversation.restore_previous_message") :
            "发送"
        let isEnabled = sendEnabled || canRestorePreviousMessage

        ZStack {
            Circle()
                .fill(isEnabled ? Color.cyan : Color.white.opacity(0.10))
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .opacity(isEnabled ? 1.0 : 0.6)
        .onTapGesture {
            guard isEnabled else { return }
            if canRestorePreviousMessage {
                restorePreviousUserMessage()
            } else {
                sendCurrentDraft()
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityIdentifier("conversation.send-button")
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
            }
            .accessibilityIdentifier("conversation.tool-sheet")
            .navigationTitle("工具与图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        isShowingToolSettings = false
                    }
                    .accessibilityIdentifier("conversation.tool-done")
                }
            }
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
        toggleVoiceRecording(startMode: .directSend)
    }

    private func toggleVoiceRecording(startMode: CompanionVoiceCaptureMode) {
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
                isDraftFieldFocused = false
                await chatStore.sendRecordedAudioDirectly(attachment, in: conversationID)
            }
        }
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
        isDraftFieldFocused = false

        Task {
            await chatStore.sendMessage(in: conversationID)
        }
    }

    private func restorePreviousUserMessage() {
        guard chatStore.restoreLatestUserMessageToDraft(for: conversationID) else {
            return
        }

        chatStore.clearError(for: conversationID)
        isDraftFieldFocused = true
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        isAutoScrollInterrupted = false
        scrollInterruptionsSuppressedUntil = Date.now.addingTimeInterval(CompanionConversationScrollLayout.suppressionDuration)

        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
            return
        }

        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
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

    private func scrollToBottomIfNeeded(
        with proxy: ScrollViewProxy,
        animated: Bool,
        autoScrollSessionMessageID: UUID?,
        force: Bool = false
    ) {
        guard force || shouldAutoScroll(for: autoScrollSessionMessageID) else {
            return
        }

        scrollToBottom(with: proxy, animated: animated)
    }

    private func shouldAutoScroll(for autoScrollSessionMessageID: UUID?) -> Bool {
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
        with proxy: ScrollViewProxy
    ) {
        if let streamingMessageID {
            activeAutoScrollSessionMessageID = streamingMessageID

            if interruptedAutoScrollSessionMessageID != nil,
               interruptedAutoScrollSessionMessageID != streamingMessageID {
                interruptedAutoScrollSessionMessageID = nil
                isAutoScrollInterrupted = false
            }

            suspendedStreamingRenderMessageID = nil
            streamingRenderResumeTask?.cancel()
            streamingRenderResumeTask = nil
            scrollToBottomIfNeeded(
                with: proxy,
                animated: false,
                autoScrollSessionMessageID: autoScrollSessionMessageID
            )
            return
        }

        if let latestAssistantMessageID {
            activeAutoScrollSessionMessageID = latestAssistantMessageID
        }

        suspendedStreamingRenderMessageID = nil
        streamingRenderResumeTask?.cancel()
        streamingRenderResumeTask = nil
        scrollToBottomIfNeeded(
            with: proxy,
            animated: false,
            autoScrollSessionMessageID: autoScrollSessionMessageID
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
        scheduleStreamingRenderResume(for: streamingMessageID)
    }

    private func scheduleStreamingRenderResume(for streamingMessageID: UUID) {
        streamingRenderResumeTask?.cancel()
        streamingRenderResumeTask = Task {
            try? await Task.sleep(nanoseconds: CompanionConversationScrollLayout.streamingRenderResumeDelayNanoseconds)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                guard suspendedStreamingRenderMessageID == streamingMessageID else {
                    return
                }

                suspendedStreamingRenderMessageID = nil
                streamingRenderResumeTask = nil
            }
        }
    }

    private func handleBottomAnchorPositionChange(
        _ maxY: CGFloat,
        autoScrollSessionMessageID: UUID?
    ) {
        guard Date.now >= scrollInterruptionsSuppressedUntil,
              messagesViewportHeight > 0
        else {
            return
        }

        let distanceFromBottom = maxY - messagesViewportHeight
        guard distanceFromBottom > CompanionConversationScrollLayout.interruptionThreshold else {
            guard interruptedAutoScrollSessionMessageID != autoScrollSessionMessageID else {
                return
            }

            isAutoScrollInterrupted = false
            return
        }

        interruptAutoScroll(for: autoScrollSessionMessageID)
    }

    private func recordingStatusTitle() -> String {
        let duration = L10n.format("conversation.recording.zh", voiceRecorder.elapsedTimeText)
        guard voiceCaptureMode == .directSend else {
            return duration
        }

        return "直接发送中 \(duration)"
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
        renderedMessageBudget = CompanionConversationRendering.prewarmedRenderBudget

        guard ConversationHistoryRenderBudget.shouldDeferInitialRendering(
            in: messages,
            threshold: CompanionConversationRendering.deferredRenderThreshold
        ) else {
            renderedMessageBudget = totalHistoryCost
            isPreparingHistory = false
            return
        }

        isPreparingHistory = true
        initialHistoryLoadTask = Task {
            try? await Task.sleep(nanoseconds: CompanionConversationRendering.initialLoadDelayNanoseconds)
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                renderedMessageBudget = min(
                    lastObservedHistoryCost,
                    CompanionConversationRendering.initialRenderBudget
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
            threshold: CompanionConversationRendering.deferredRenderThreshold
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
                    CompanionConversationRendering.prewarmedRenderBudget
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
        let totalHistoryCost = ConversationHistoryRenderBudget.totalCost(in: messages)
        guard totalHistoryCost > 0 else {
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
                CompanionConversationRendering.initialRenderBudget
            ),
            preferredIncrement: CompanionConversationRendering.olderRenderBudget
        )
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

    private func currentToolSettingsDraft() -> CompanionToolSettingsDraft {
        let configuration = chatStore.aiConfiguration(for: conversationID)
        return CompanionToolSettingsDraft(
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

    private func isPredominantlyVertical(_ translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width)
    }

    private func latestAssistantMessageID(in messages: [ChatMessage]) -> UUID? {
        messages.last(where: { $0.role == .assistant })?.id
    }
}

private struct CompanionConversationViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompanionConversationBottomAnchorMaxYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompanionHeaderMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.56))

            OverflowScrollingText(
                text: value,
                font: .caption.weight(.semibold),
                color: .white,
                gap: 18,
                speed: 24,
                expandsHorizontally: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct CompanionComposerMenuLabel: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan.opacity(0.92))

            OverflowScrollingText(
                text: title,
                font: .caption.weight(.semibold),
                color: .white,
                gap: 18,
                speed: 24,
                expandsHorizontally: true
            )
            .layoutPriority(1)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct CompanionInlineStatus: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.cyan)
            OverflowScrollingText(
                text: title,
                font: .subheadline,
                color: .white.opacity(0.88),
                gap: 18,
                speed: 24,
                expandsHorizontally: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

private struct CompanionDraftAttachmentCard: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = attachment.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                            .overlay(
                                Image(systemName: attachment.isAudio ? "waveform" : "photo")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            )
                    }
                }
                .frame(width: 112, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }

            OverflowScrollingText(
                text: attachment.filename,
                font: .caption,
                color: .white.opacity(0.82),
                gap: 18,
                speed: 22,
                expandsHorizontally: true
            )
        }
    }
}

private struct CompanionComposerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
#endif
