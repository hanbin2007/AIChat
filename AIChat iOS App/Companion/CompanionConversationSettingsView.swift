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

    @State private var draft = ConversationSettingsDraft(title: "", systemPrompt: "")
    @State private var isShowingPromptPresetPicker = false
    @State private var pendingDestructiveAction: DestructiveAction?

    var body: some View {
        NavigationStack {
            Form {
                Section("会话") {
                    TextField("标题", text: $draft.title)
                        .disabled(chatStore.isReadOnlyMode)

                    Button("保存标题") {
                        Task {
                            await chatStore.renameConversation(id: conversationID, title: draft.title)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode || draft.title.trimmed.isEmpty)

                    Button("清空消息", role: .destructive) {
                        pendingDestructiveAction = .clearMessages
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
                                text: $draft.systemPrompt,
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

                            if chatStore.isReadOnlyMode == false, draft.isSystemPromptDirty {
                                Button("保存系统提示词") {
                                    Task {
                                        await saveSystemPrompt()
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("放弃系统提示词更改") {
                                    draft.revertSystemPrompt()
                                }
                            }

                            if chatStore.isReadOnlyMode == false, draft.systemPrompt.trimmed.isEmpty == false {
                                Button("清空系统提示词", role: .destructive) {
                                    draft.systemPrompt = ""
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
                                            pendingDestructiveAction = .removePinnedMemory(item.id)
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
                        pendingDestructiveAction = .deleteConversation
                    }
                    .accessibilityIdentifier("companion.conversation.settings.delete")
                }
            }
            .accessibilityIdentifier("companion.conversation.settings")
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
                        draft.systemPrompt = preset.content
                    }
                )
            }
            .alert(item: $pendingDestructiveAction) { action in
                Alert(
                    title: Text(action.title),
                    message: Text(action.message),
                    primaryButton: .destructive(Text(action.confirmTitle)) {
                        Task {
                            await performDestructiveAction(action)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                draft = ConversationSettingsDraft(
                    title: chatStore.conversation(id: conversationID)?.title ?? "",
                    systemPrompt: chatStore.aiConfiguration(for: conversationID).customSystemPrompt ?? ""
                )
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

    private func saveSystemPrompt() async {
        guard chatStore.isReadOnlyMode == false,
              let prompt = draft.systemPromptSavePayload()
        else {
            return
        }

        await chatStore.updateCustomSystemPrompt(prompt, for: conversationID)
        draft.markSystemPromptSaved()
    }

    private func performDestructiveAction(_ action: DestructiveAction) async {
        switch action {
        case .clearMessages:
            await chatStore.clearConversation(id: conversationID)
            dismiss()
        case .deleteConversation:
            await chatStore.deleteConversation(id: conversationID)
            dismiss()
        case .removePinnedMemory(let memoryID):
            await chatStore.removePinnedMemory(id: memoryID, from: conversationID)
        }
    }

    private func globalMemoryBinding(for conversationID: UUID) -> Binding<Bool> {
        Binding(
            get: {
                chatStore.aiConfiguration(for: conversationID).usesGlobalPinnedMemory
            },
            set: { newValue in
                chatStore.setUsesGlobalPinnedMemory(newValue, for: conversationID)
            }
        )
    }

    private enum DestructiveAction: Identifiable {
        case clearMessages
        case deleteConversation
        case removePinnedMemory(UUID)

        var id: String {
            switch self {
            case .clearMessages:
                return "clearMessages"
            case .deleteConversation:
                return "deleteConversation"
            case .removePinnedMemory(let memoryID):
                return "removePinnedMemory-\(memoryID.uuidString)"
            }
        }

        var title: String {
            switch self {
            case .clearMessages:
                return "清空消息？"
            case .deleteConversation:
                return "删除会话？"
            case .removePinnedMemory:
                return "删除固定记忆？"
            }
        }

        var message: String {
            switch self {
            case .clearMessages:
                return "这个会话中的所有消息都会被移除。"
            case .deleteConversation:
                return "这个会话会从当前设备移除。"
            case .removePinnedMemory:
                return "这条记忆将不再固定到当前会话。"
            }
        }

        var confirmTitle: String {
            switch self {
            case .clearMessages:
                return "清空消息"
            case .deleteConversation:
                return "删除会话"
            case .removePinnedMemory:
                return "删除固定记忆"
            }
        }
    }
}
#endif
