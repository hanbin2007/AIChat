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
    @State private var draftSystemPrompt = ""

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

                if let conversation = chatStore.conversation(id: conversationID) {
                    let aiConfiguration = chatStore.aiConfiguration(for: conversation.id)

                    Section("AI") {
                        LabeledContent("Model", value: AIModelCatalog.displayName(for: aiConfiguration.model))
                        LabeledContent("Thinking", value: aiConfiguration.thinkingIntensity.displayName)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Prompt")
                                .font(.headline)

                            TextField(
                                "Use the built-in prompt",
                                text: $draftSystemPrompt,
                                axis: .vertical
                            )
                            .disabled(chatStore.isReadOnlyMode)

                            Text(systemPromptHint(for: aiConfiguration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button("Save Prompt") {
                                Task {
                                    await chatStore.updateCustomSystemPrompt(
                                        draftSystemPrompt,
                                        for: conversation.id
                                    )
                                }
                            }
                            .disabled(chatStore.isReadOnlyMode)

                            if draftSystemPrompt.trimmed.isEmpty == false {
                                Button("Clear Prompt", role: .destructive) {
                                    draftSystemPrompt = ""
                                    Task {
                                        await chatStore.updateCustomSystemPrompt(
                                            "",
                                            for: conversation.id
                                        )
                                    }
                                }
                                .disabled(chatStore.isReadOnlyMode)
                            }
                        }
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
                draftSystemPrompt = chatStore.aiConfiguration(for: conversationID).customSystemPrompt ?? ""
            }
        }
    }

    private func systemPromptHint(for configuration: ConversationAIConfiguration) -> String {
        if configuration.systemPromptMode == .default,
           configuration.customSystemPrompt == nil {
            return "Leave this empty to send no system prompt. Enter text here to use a custom system prompt."
        }

        return "Leave this empty to use the built-in system prompt for new replies."
    }
}
#endif
