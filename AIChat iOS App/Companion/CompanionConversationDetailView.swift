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

struct CompanionConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var isShowingToolSettings = false
    @State private var isShowingActivationCenter = false
    @State private var interruptedAutoScrollMessageID: UUID?
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
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            CompanionConversationSettingsView(conversationID: conversationID)
        }
        .sheet(isPresented: $isShowingToolSettings) {
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
    }

    private func conversationContent(_ conversation: ConversationThread) -> some View {
        let streamingMessageID = currentStreamingMessageID(in: conversation)
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
                                suspendStreamingRender: suspendedStreamingRenderMessageID == message.id
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
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        pauseStreamingRefresh(for: streamingMessageID)
                    }
            )
            .onPreferenceChange(CompanionConversationViewportHeightPreferenceKey.self) { height in
                messagesViewportHeight = height
            }
            .onPreferenceChange(CompanionConversationBottomAnchorMaxYPreferenceKey.self) { maxY in
                handleBottomAnchorPositionChange(maxY, streamingMessageID: streamingMessageID)
            }
            .onAppear {
                interruptedAutoScrollMessageID = nil
                suspendedStreamingRenderMessageID = nil
                pendingHistoryAnchorMessageID = nil
                streamingRenderResumeTask?.cancel()
                streamingRenderResumeTask = nil
                prepareInitialHistoryIfNeeded(messages: conversation.messages)
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID,
                    force: true
                )
            }
            .onChange(of: conversation.messages.count) { _ in
                reconcileRenderedHistory(with: conversation.messages)
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: true,
                    streamingMessageID: streamingMessageID
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
                    streamingMessageID: streamingMessageID,
                    force: true
                )
            }
            .onChange(of: conversation.updatedAt) { _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID
                )
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _ in
                scrollToBottomIfNeeded(
                    with: proxy,
                    animated: false,
                    streamingMessageID: streamingMessageID
                )
            }
            .onChange(of: streamingMessageID) { newMessageID in
                handleStreamingMessageChange(
                    newMessageID,
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
        let hasDraftContent = draftText.nonEmptyTrimmed != nil || attachments.isEmpty == false
        let isTranscribing = chatStore.isTranscribing(conversationID: conversationID)
        let isSending = chatStore.isSending(conversationID: conversationID)
        let sendEnabled = hasDraftContent && isSending == false && isTranscribing == false && voiceRecorder.isInteractive
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
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                    .tint(voiceRecorder.isRecording ? .red : .white)
                    .disabled(voiceButtonDisabled)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in
                                handleVoiceButtonLongPress()
                            }
                    )

                    Button {
                        isShowingToolSettings = true
                    } label: {
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
                    .accessibilityLabel(toolButtonAccessibilityLabel(for: aiConfiguration))

                    Button {
                        sendCurrentDraft()
                    } label: {
                        Label("发送", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(sendEnabled == false)
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
            .fill(Color.black.opacity(0.78))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
    }

    private var conversationToolSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("联网搜索", isOn: googleSearchEnabledBinding())
                    Toggle("运行代码", isOn: codeExecutionEnabledBinding())
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
                }
            }
            .navigationTitle("工具与图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        isShowingToolSettings = false
                    }
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

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
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
            return interruptedAutoScrollMessageID == nil
        }

        return interruptedAutoScrollMessageID != streamingMessageID
    }

    private func handleStreamingMessageChange(
        _ streamingMessageID: UUID?,
        with proxy: ScrollViewProxy
    ) {
        if let streamingMessageID {
            interruptedAutoScrollMessageID = nil
            suspendedStreamingRenderMessageID = nil
            streamingRenderResumeTask?.cancel()
            streamingRenderResumeTask = nil
            scrollToBottomIfNeeded(
                with: proxy,
                animated: false,
                streamingMessageID: streamingMessageID,
                force: true
            )
            return
        }

        suspendedStreamingRenderMessageID = nil
        streamingRenderResumeTask?.cancel()
        streamingRenderResumeTask = nil
        scrollToBottomIfNeeded(
            with: proxy,
            animated: false,
            streamingMessageID: nil
        )
    }

    private func interruptAutoScroll(for streamingMessageID: UUID?) {
        guard let streamingMessageID else {
            return
        }

        interruptedAutoScrollMessageID = streamingMessageID
    }

    private func interruptAutoScrollImmediately(for streamingMessageID: UUID?) {
        guard interruptedAutoScrollMessageID != streamingMessageID else {
            return
        }

        scrollInterruptionsSuppressedUntil = .distantPast
        interruptAutoScroll(for: streamingMessageID)
    }

    private func pauseStreamingRefresh(for streamingMessageID: UUID?) {
        interruptAutoScrollImmediately(for: streamingMessageID)
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

    private func handleBottomAnchorPositionChange(_ maxY: CGFloat, streamingMessageID: UUID?) {
        guard let streamingMessageID,
              Date.now >= scrollInterruptionsSuppressedUntil,
              messagesViewportHeight > 0
        else {
            return
        }

        let distanceFromBottom = maxY - messagesViewportHeight
        guard distanceFromBottom > CompanionConversationScrollLayout.interruptionThreshold else {
            return
        }

        interruptAutoScroll(for: streamingMessageID)
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
                chatStore.aiConfiguration(for: conversationID).usesGoogleSearch
            },
            set: { newValue in
                Task {
                    await chatStore.updateGoogleSearchEnabled(newValue, for: conversationID)
                }
            }
        )
    }

    private func codeExecutionEnabledBinding() -> Binding<Bool> {
        Binding(
            get: {
                chatStore.aiConfiguration(for: conversationID).usesCodeExecution
            },
            set: { newValue in
                Task {
                    await chatStore.updateCodeExecutionEnabled(newValue, for: conversationID)
                }
            }
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
#endif
