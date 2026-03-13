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
    @State private var isShowingPromptPresetPicker = false

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
                    LabeledContent("Version", value: chatStore.appVersionDescription)
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

                            Button(L10n.tr("prompt_preset.pick")) {
                                isShowingPromptPresetPicker = true
                            }
                            .disabled(chatStore.isReadOnlyMode || chatStore.promptPresets(of: .conversation).isEmpty)

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

                    Section("记忆") {
                        Toggle("调用全局记忆", isOn: globalMemoryBinding(for: conversation.id))
                            .disabled(chatStore.isReadOnlyMode)

                        LabeledContent("全局记忆条目", value: "\(chatStore.globalPinnedMemories.count)")

                        Text("开启后，这个会话会在本地记忆之外额外召回全局固定记忆。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section("本会话固定记忆") {
                        if conversation.pinnedMemories.isEmpty {
                            Text("还没有固定记忆。可以在消息菜单里把重要内容固定到当前会话。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(conversation.pinnedMemories) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.text)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    if chatStore.isReadOnlyMode == false {
                                        Button("删除固定记忆", role: .destructive) {
                                            Task {
                                                await chatStore.removePinnedMemory(id: item.id, from: conversation.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
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
            .sheet(isPresented: $isShowingPromptPresetPicker) {
                PromptPresetPickerView(
                    kind: .conversation,
                    title: L10n.tr("prompt_preset.library.title"),
                    onSelect: { preset in
                        draftSystemPrompt = preset.content
                    }
                )
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
            return L10n.tr("system_prompt.hint.none")
        }

        return L10n.tr("system_prompt.hint.builtin")
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

    private func globalMemoryBinding(for conversationID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                chatStore.aiConfiguration(for: conversationID).usesGlobalPinnedMemory
            },
            set: { newValue in
                Task {
                    await chatStore.updateUsesGlobalPinnedMemory(newValue, for: conversationID)
                }
            }
        )
    }
}
#endif
