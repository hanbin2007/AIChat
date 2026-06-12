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
    @Environment(\.colorScheme) private var colorScheme
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
        .onChange(of: selectedPhotoItems) { _, items in
            Task {
                await importPickedItems(items)
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
                                streamingPacer: chatStore.streamingPacer,
                                onPinMessage: { messageID, convoID, scope in
                                    await chatStore.pinMessage(id: messageID, from: convoID, scope: scope)
                                }
                            )
                                .equatable()
                                .id(message.id)
                        }
                    }

                    if let errorMessage = chatStore.errorMessage(for: conversationID) {
                        failedReplyBanner(errorMessage)
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
            .onChange(of: conversation.messages.count) {
                reconcileRenderedHistory(with: conversation.messages)
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: true,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
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

                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: conversation.updatedAt) {
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) {
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    autoScrollSessionMessageID: autoScrollSessionMessageID
                )
            }
            .onChange(of: chatStore.isGlobalAutoScrollEnabled) { _, isEnabled in
                if isEnabled {
                    isAutoScrollInterrupted = false
                    interruptedAutoScrollSessionMessageID = nil
                    scrollToBottomIfNeeded(
                        with: proxy,
                        animated: true,
                        autoScrollSessionMessageID: autoScrollSessionMessageID,
                        force: true
                    )
                }
            }
            .onChange(of: streamingMessageID) { _, newMessageID in
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
                .foregroundStyle(DS.Text.primary(for: colorScheme))

            Text("继续这条会话，和手表实时同步。")
                .font(.subheadline)
                .foregroundStyle(DS.Text.secondary(for: colorScheme))

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
                            DS.Surface.elevatedStrongFill(for: colorScheme),
                            DS.Surface.elevatedFill(for: colorScheme)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(chatStore.isReadOnlyMode ? "当前设备只读" : "继续对话")
                .font(.headline)
                .foregroundStyle(DS.Text.primary(for: colorScheme))

            Text(
                chatStore.isReadOnlyMode ?
                "先看同步历史；激活后再继续发消息。" :
                "直接输入、录音，或加图片。"
            )
            .font(.subheadline)
            .foregroundStyle(DS.Text.secondary(for: colorScheme))

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
                .fill(DS.Surface.elevatedFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
                )
        )
    }

    private func starterChip(_ text: String) -> some View {
        Button(text) {
            chatStore.updateDraftText(text, for: conversationID)
        }
        .buttonStyle(.bordered)
        .tint(DS.Text.primary(for: colorScheme))
    }

    private func historyLoadingCard(visibleCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                Text("正在准备历史消息")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Text.primary(for: colorScheme))

                Text("先显示最近 \(visibleCount) / \(totalCount) 条，等导航稳定后再继续。")
                    .font(.footnote)
                    .foregroundStyle(DS.Text.secondary(for: colorScheme))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(DS.Surface.elevatedFill(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
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
                        .foregroundStyle(DS.Text.primary(for: colorScheme))

                    Text("还有 \(hiddenMessageCount) 条未渲染，当前显示最近 \(visibleCount) / \(totalCount) 条。")
                        .font(.footnote)
                        .foregroundStyle(DS.Text.secondary(for: colorScheme))
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
                    .fill(DS.Surface.elevatedFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(DS.Surface.elevatedStroke(for: colorScheme), lineWidth: 1)
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
        let primaryButtonTitle =
            isSending ? "停止回复" :
            (canRestorePreviousMessage ? L10n.tr("conversation.restore_previous_message") : "发送")
        let primaryButtonIconName =
            isSending ? "stop.fill" :
            (canRestorePreviousMessage ? "arrow.uturn.backward.circle.fill" : "arrow.up.circle.fill")
        let voiceButtonLabel =
            voiceRecorder.isRecording ?
            (voiceCaptureMode == .directSend ? "停止并发送" : "停止并转录") :
            "语音"
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

                TextField("Ask Gemini", text: draftTextBinding(), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(DS.Text.primary(for: colorScheme))
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(DS.Surface.subtleFill(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(DS.Surface.subtleStroke(for: colorScheme), lineWidth: 1)
                    )
                    .tint(.cyan)
                    .focused($isDraftFieldFocused)
                    .disabled(voiceRecorder.isRecording || isTranscribing)

                HStack(spacing: 10) {
                    Button {
                        handleVoiceButtonTap()
                    } label: {
                        Label(voiceButtonLabel, systemImage: voiceRecorder.isRecording ? "stop.fill" : "waveform.badge.mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(voiceRecorder.isRecording ? .red : DS.Text.primary(for: colorScheme))
                    .disabled(voiceButtonDisabled)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in
                                handleVoiceButtonLongPress()
                            }
                    )

                    Button(action: presentToolSettings) {
                        HStack(spacing: 6) {
                            ForEach(toolButtonSymbols(for: aiConfiguration), id: \.self) { symbolName in
                                Image(systemName: symbolName)
                            }

                            Text("工具/图片")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(toolButtonTint(for: aiConfiguration))
                    .disabled(voiceRecorder.isRecording || isTranscribing)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(toolButtonAccessibilityLabel(for: aiConfiguration))
                    .accessibilityValue(toolButtonAccessibilityValue(for: aiConfiguration))
                    .accessibilityIdentifier("conversation.tool-entry")

                    Button {
                        if isSending {
                            stopCurrentReply()
                        } else if canRestorePreviousMessage {
                            restorePreviousUserMessage()
                        } else {
                            sendCurrentDraft()
                        }
                    } label: {
                        Label(
                            primaryButtonTitle,
                            systemImage: primaryButtonIconName
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSending ? .red : .cyan)
                    .disabled(isSending ? false : (sendEnabled || canRestorePreviousMessage) == false)
                    .accessibilityLabel(primaryButtonTitle)
                    .accessibilityIdentifier("conversation.send.primary")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(companionComposerBackground.ignoresSafeArea(.container, edges: .bottom))
        }
    }

    private var companionComposerBackground: some View {
        Rectangle()
            .fill(DS.Surface.elevatedStrongFill(for: colorScheme))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DS.Surface.elevatedStroke(for: colorScheme))
                    .frame(height: 1)
            }
    }

    private func failedReplyBanner(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ConfigurationBannerView(
                iconName: "exclamationmark.triangle.fill",
                title: "发送失败",
                message: errorMessage
            )

            if chatStore.canRetryLatestReply(in: conversationID) {
                Button {
                    retryLatestReply()
                } label: {
                    Label("重试上一条回复", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .accessibilityIdentifier("conversation.retry-latest")
            }
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

    private func retryLatestReply() {
        guard chatStore.isReadOnlyMode == false else {
            isShowingActivationCenter = true
            return
        }

        guard chatStore.canRetryLatestReply(in: conversationID) else {
            return
        }

        chatStore.clearError(for: conversationID)
        isDraftFieldFocused = false

        Task {
            await chatStore.retryLatestReply(in: conversationID)
        }
    }

    private func stopCurrentReply() {
        chatStore.stopSending(in: conversationID)
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
        (configuration.usesGoogleSearch || configuration.usesCodeExecution) ? .cyan : DS.Text.primary(for: colorScheme)
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
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Text.tertiary(for: colorScheme))

            OverflowScrollingText(
                text: value,
                font: .caption.weight(.semibold),
                color: DS.Text.primary(for: colorScheme),
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
                .fill(DS.Surface.subtleFill(for: colorScheme))
        )
    }
}

private struct CompanionComposerMenuLabel: View {
    @Environment(\.colorScheme) private var colorScheme

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
                color: DS.Text.primary(for: colorScheme),
                gap: 18,
                speed: 24,
                expandsHorizontally: true
            )
            .layoutPriority(1)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DS.Text.tertiary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.Surface.subtleFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Surface.subtleStroke(for: colorScheme), lineWidth: 1)
        )
    }
}

private struct CompanionInlineStatus: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.cyan)
            OverflowScrollingText(
                text: title,
                font: .subheadline,
                color: DS.Text.primary(for: colorScheme),
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
                .fill(DS.Surface.subtleFill(for: colorScheme))
        )
    }
}

private struct CompanionDraftAttachmentCard: View {
    @Environment(\.colorScheme) private var colorScheme

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
                        .foregroundStyle(.white, .black.opacity(0.72))
                        .shadow(radius: 6)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityIdentifier("conversation.draft-attachment.remove")
            }
            .accessibilityIdentifier("conversation.draft-attachment.preview")

            OverflowScrollingText(
                text: attachment.filename,
                font: .caption,
                color: DS.Text.secondary(for: colorScheme),
                gap: 18,
                speed: 22,
                expandsHorizontally: true
            )
        }
    }
}
#endif
