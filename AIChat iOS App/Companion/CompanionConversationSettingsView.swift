#if COMPANION_APP
//
//  CompanionConversationSettingsView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

struct CompanionConversationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @State private var draftTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("会话") {
                    TextField("标题", text: $draftTitle)
                        .disabled(chatStore.isReadOnlyMode)

                    Button("保存标题") {
                        Task {
                            await chatStore.renameConversation(id: conversationID, title: draftTitle)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode || draftTitle.trimmed.isEmpty)

                    Button("清空消息", role: .destructive) {
                        Task {
                            await chatStore.clearConversation(id: conversationID)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode)
                }

                Section("运行时") {
                    LabeledContent("Backend", value: chatStore.configuration.backendSummary)
                    LabeledContent("Storage", value: chatStore.storageDescription)
                    LabeledContent("Sync", value: chatStore.syncStatusDescription)
                    LabeledContent("Activation", value: chatStore.activationStatusTitle)
                }

                if let conversation = chatStore.conversation(id: conversationID) {
                    let aiConfiguration = chatStore.aiConfiguration(for: conversation.id)

                    Section("AI") {
                        LabeledContent("模型", value: AIModelCatalog.displayName(for: aiConfiguration.model))
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

                Section("危险操作") {
                    Button("删除会话", role: .destructive) {
                        Task {
                            await chatStore.deleteConversation(id: conversationID)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode)
                }
            }
            .navigationTitle("会话设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
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
}
#endif
