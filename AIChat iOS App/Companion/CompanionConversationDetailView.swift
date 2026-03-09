#if COMPANION_APP
//
//  CompanionConversationDetailView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import PhotosUI
import SwiftUI

struct CompanionConversationDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isShowingSettings = false
    @State private var isShowingActivationCenter = false

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
    }

    private func conversationContent(_ conversation: ConversationThread) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    conversationHeaderCard(conversation: conversation)

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
                            title: "发送失败",
                            message: errorMessage
                        )
                        .id("conversation-error")
                    }

                    Color.clear
                        .frame(height: 6)
                        .id(bottomAnchorID)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
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
            .onAppear {
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: conversation.messages.count) { _ in
                scrollToBottom(with: proxy, animated: true)
            }
            .onChange(of: conversation.updatedAt) { _ in
                scrollToBottom(with: proxy, animated: false)
            }
            .onChange(of: chatStore.isSending(conversationID: conversationID)) { _ in
                scrollToBottom(with: proxy, animated: false)
            }
        }
    }

    private func conversationHeaderCard(conversation: ConversationThread) -> some View {
        let configuration = chatStore.aiConfiguration(for: conversation.id)

        return VStack(alignment: .leading, spacing: 14) {
            Text(conversation.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("在 iPhone 上继续处理这条会话，设置会和手表同步保持一致。")
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
            Text(chatStore.isReadOnlyMode ? "当前设备只读" : "从 iPhone 继续")
                .font(.headline)
                .foregroundStyle(.white)

            Text(
                chatStore.isReadOnlyMode ?
                "这条会话已经同步到 iPhone。完成当前设备激活后，就能在这里继续发消息、录音和上传图片。" :
                "可以直接输入问题、录一段语音、先转录再发送，或者上传图片走多模态分析。"
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
                        title: voiceRecorder.isRecording ? "录音中 \(voiceRecorder.elapsedTimeText)" : "准备麦克风..."
                    )
                } else if isTranscribing {
                    CompanionInlineStatus(
                        iconName: "waveform.and.magnifyingglass",
                        title: "正在用 \(AITranscriptionModelCatalog.shortLabel(for: chatStore.selectedTranscriptionModel)) 转录语音"
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
                    .disabled(voiceRecorder.isRecording || isTranscribing)

                HStack(spacing: 10) {
                    Button {
                        toggleVoiceRecording()
                    } label: {
                        Label(voiceRecorder.isRecording ? "停止并转录" : "语音", systemImage: voiceRecorder.isRecording ? "stop.fill" : "waveform.badge.mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(voiceRecorder.isRecording ? .red : .white)
                    .disabled(
                        voiceRecorder.isRecording == false &&
                        (isSending || isTranscribing || voiceRecorder.isPreparing || hasDraftContent)
                    )

                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 3,
                        matching: .images
                    ) {
                        Label("图片", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(voiceRecorder.isRecording || isTranscribing)

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

        Task {
            await chatStore.sendMessage(in: conversationID)
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
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
