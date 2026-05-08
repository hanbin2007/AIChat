//
//  ConversationDetailView.swift
//  AIChat Watch App
//
//  Renders one conversation: scrollable message list above, composer
//  below. Modal surfaces:
//    • voice recorder sheet
//    • tool menu sheet
//    • inline low-balance CTA
//    • inline retry on the last failed assistant message
//
//  Auto-scroll uses SwiftUI's `ScrollViewReader`. The richer
//  Auto-scroll Controller (design doc §1.2) will replace this hook
//  later; the view only needs to keep talking to a ScrollViewReader,
//  so the swap is local.
//
//  Always-on-display: the entire scroll body is wrapped with
//  `aodPrivacy()` — luminance-reduced state redacts the bubbles.
//

import SwiftUI

struct ConversationDetailView: View {
    @Bindable var viewModel: ConversationDetailViewModel
    let settings: SettingsService
    let allowedModelIDs: Set<String>?

    @State private var draft: String = ""
    @State private var presentingVoice: Bool = false
    @State private var presentingTools: Bool = false
    @Environment(\.appEnvironment) private var environment

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if viewModel.lowBalanceVisible {
                lowBalanceCTA
            }
            ComposerBar(
                draft: $draft,
                canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isStreaming: viewModel.sendState == .streaming || viewModel.sendState == .sending,
                onSend: send,
                onCancelStream: viewModel.cancelStream,
                onMicrophone: { presentingVoice = true },
                onTools: { presentingTools = true }
            )
        }
        .navigationTitle(viewModel.conversation.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.conversationSettings(viewModel.conversation.id)) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation settings")
            }
        }
        .sheet(isPresented: $presentingVoice) {
            voiceSheet
        }
        .sheet(isPresented: $presentingTools) {
            ToolMenu(
                configuration: resolvedConfiguration,
                allowedModelIDs: allowedModelIDs,
                onUpdate: { config in
                    viewModel.updateAIConfiguration(config)
                },
                onOpenFullSettings: {
                    presentingTools = false
                    // The toolbar link path-pushes settings; here we
                    // rely on the user tapping the toolbar button.
                },
                onDismiss: { presentingTools = false }
            )
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.s) {
                    ForEach(visibleMessages) { message in
                        ChatBubbleView(
                            message: message,
                            isLastStreaming: isLastStreaming(message),
                            onRetry: message.id == failedAssistantID ? viewModel.retryLast : nil
                        )
                        .id(message.id)
                    }
                    if let error = sendErrorMessage {
                        sendErrorView(error)
                    }
                }
                .padding(.horizontal, DS.Spacing.s)
                .padding(.vertical, DS.Spacing.s)
            }
            .aodPrivacy()
            .onChange(of: viewModel.conversation.messages.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var visibleMessages: [ChatMessage] {
        let messages = viewModel.conversation.messages
        let budget = 12
        let visibleCount = ConversationHistoryRenderBudget.visibleMessageCount(in: messages, budget: budget)
        guard visibleCount < messages.count else {
            return messages
        }
        return Array(messages.suffix(visibleCount))
    }

    private func isLastStreaming(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant,
              message.status == .streaming else { return false }
        return message.id == viewModel.conversation.messages.last?.id
    }

    private var failedAssistantID: UUID? {
        guard let last = viewModel.conversation.messages.last,
              last.role == .assistant,
              last.status == .failed else { return nil }
        return last.id
    }

    private var sendErrorMessage: String? {
        if case .failed(let message) = viewModel.sendState { return message }
        return nil
    }

    private func sendErrorView(_ message: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Status.danger)
            Text(message)
                .font(DS.Typography.bubbleMeta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, DS.Spacing.s)
    }

    // MARK: - Composer & send

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.send(text: text, attachments: [])
        draft = ""
    }

    // MARK: - Low balance

    private var lowBalanceCTA: some View {
        NavigationLink(value: Route.accountCenter) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "exclamationmark.circle")
                Text("Low balance")
                    .font(DS.Typography.bubbleMeta)
                Spacer()
                Text("Top up")
                    .font(DS.Typography.chip)
                    .foregroundStyle(DS.Status.info)
            }
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.xs)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Voice sheet

    private var voiceSheet: some View {
        VoiceRecorderView(
            onComplete: { attachment in
                presentingVoice = false
                Task { await transcribe(attachment) }
            },
            onCancel: {
                presentingVoice = false
            }
        )
    }

    private func transcribe(_ audio: ChatAttachment) async {
        let transcript = await viewModel.transcribe(
            audio,
            model: settings.transcriptionModel,
            customPrompt: settings.transcriptionCustomPrompt,
            includesContext: settings.transcriptionIncludesContext,
            existingDraft: draft
        )
        if let transcript {
            // Append the transcript to whatever draft already exists;
            // user can edit or send.
            if draft.isEmpty {
                draft = transcript
            } else {
                draft = draft + " " + transcript
            }
        }
    }

    // MARK: - Resolved configuration

    private var resolvedConfiguration: ConversationAIConfiguration {
        viewModel.conversation.aiConfiguration ?? settings.defaultConversationConfiguration
    }
}
