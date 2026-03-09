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
    @State private var draftSystemPrompt = ""
    @State private var promptSaveTask: Task<Void, Never>?

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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("系统提示词")
                                .font(.headline)

                            TextField(
                                "留空则使用默认系统提示词",
                                text: $draftSystemPrompt,
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(chatStore.isReadOnlyMode)

                            Text(systemPromptHint(for: aiConfiguration))
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if chatStore.isReadOnlyMode == false, draftSystemPrompt.trimmed.isEmpty == false {
                                Button("清空系统提示词", role: .destructive) {
                                    draftSystemPrompt = ""
                                }
                            }
                        }
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
                draftSystemPrompt = chatStore.aiConfiguration(for: conversationID).customSystemPrompt ?? ""
            }
            .onChange(of: draftSystemPrompt) { newValue in
                schedulePromptSave(newValue)
            }
            .onDisappear {
                promptSaveTask?.cancel()
                Task {
                    await chatStore.updateCustomSystemPrompt(draftSystemPrompt, for: conversationID)
                }
            }
        }
    }

    private func systemPromptHint(for configuration: ConversationAIConfiguration) -> String {
        if configuration.systemPromptMode == .default,
           configuration.customSystemPrompt == nil {
            return "留空时当前会话不会发送系统提示词；输入内容后会改为使用自定义系统提示词。"
        }

        return "留空时继续使用内置系统提示词。"
    }

    private func schedulePromptSave(_ prompt: String) {
        promptSaveTask?.cancel()
        guard chatStore.isReadOnlyMode == false else {
            return
        }

        promptSaveTask = Task { [conversationID, prompt] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard Task.isCancelled == false else {
                return
            }

            await chatStore.updateCustomSystemPrompt(prompt, for: conversationID)
        }
    }
}
#endif
