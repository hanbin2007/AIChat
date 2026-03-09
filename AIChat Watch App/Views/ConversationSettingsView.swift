//
//  ConversationSettingsView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
struct ConversationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @State private var draftTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Conversation") {
                    TextField("Title", text: $draftTitle)
                        .disabled(chatStore.isReadOnlyMode)

                    Button("Save Title") {
                        Task {
                            await chatStore.renameConversation(id: conversationID, title: draftTitle)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode || draftTitle.trimmed.isEmpty)

                    Button("Clear Messages", role: .destructive) {
                        Task {
                            await chatStore.clearConversation(id: conversationID)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode)
                }

                Section("Runtime") {
                    LabeledContent("Backend", value: chatStore.configuration.backendSummary)
                    LabeledContent("Storage", value: chatStore.storageDescription)
                    LabeledContent("Sync", value: chatStore.syncStatusDescription)
                    LabeledContent("Activation", value: chatStore.activationStatusTitle)
                }

                Section("Requests") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto Retry")
                                .font(.headline)
                                .lineLimit(1)

                            Text("Retry failed sends and voice transcriptions up to \(chatStore.sendFailureRetryLimit) times.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 10) {
                            retryAdjustmentButton(
                                systemImage: "minus",
                                action: {
                                    chatStore.updateSendFailureRetryLimit(chatStore.sendFailureRetryLimit - 1)
                                }
                            )
                            .disabled(chatStore.sendFailureRetryLimit <= ChatStore.minimumSendFailureRetryLimit)

                            Spacer(minLength: 0)

                            Text("\(chatStore.sendFailureRetryLimit)")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .frame(minWidth: 36)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )

                            Spacer(minLength: 0)

                            retryAdjustmentButton(
                                systemImage: "plus",
                                action: {
                                    chatStore.updateSendFailureRetryLimit(chatStore.sendFailureRetryLimit + 1)
                                }
                            )
                            .disabled(chatStore.sendFailureRetryLimit >= ChatStore.maximumSendFailureRetryLimit)
                        }
                    }

                    Picker("Voice Model", selection: transcriptionModelBinding()) {
                        ForEach(chatStore.availableTranscriptionModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                if let conversation = chatStore.conversation(id: conversationID) {
                    let aiConfiguration = chatStore.aiConfiguration(for: conversation.id)

                    Section("AI") {
                        LabeledContent("Model", value: AIModelCatalog.displayName(for: aiConfiguration.model))
                        LabeledContent("Thinking", value: aiConfiguration.thinkingIntensity.displayName)
                        LabeledContent("Prompt", value: aiConfiguration.systemPromptMode.displayName)

                        Picker("System Prompt", selection: systemPromptModeBinding(for: conversation.id)) {
                            ForEach(AISystemPromptMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .disabled(chatStore.isReadOnlyMode)
                    }
                }

                Section("Danger Zone") {
                    Button("Delete Conversation", role: .destructive) {
                        Task {
                            await chatStore.deleteConversation(id: conversationID)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode)
                }
            }
            .navigationTitle("Manage Chat")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                draftTitle = chatStore.conversation(id: conversationID)?.title ?? ""
            }
        }
    }

    private func systemPromptModeBinding(for conversationID: UUID) -> Binding<AISystemPromptMode> {
        Binding(
            get: {
                chatStore.aiConfiguration(for: conversationID).systemPromptMode
            },
            set: { newValue in
                Task {
                    await chatStore.updateSystemPromptMode(newValue, for: conversationID)
                }
            }
        )
    }

    private func transcriptionModelBinding() -> Binding<String> {
        Binding(
            get: {
                chatStore.selectedTranscriptionModel
            },
            set: { newValue in
                chatStore.updateTranscriptionModel(newValue)
            }
        )
    }

    private func retryAdjustmentButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}
#endif
