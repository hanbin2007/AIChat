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

    @State private var draft = ConversationSettingsDraft(title: "", systemPrompt: "")
    @State private var isShowingPromptPresetPicker = false
    @State private var pendingDestructiveAction: DestructiveAction?

    var body: some View {
        NavigationStack {
            List {
                Section("Conversation") {
                    TextField("Title", text: $draft.title)
                        .disabled(chatStore.isReadOnlyMode)

                    Button("Save Title") {
                        Task {
                            await chatStore.renameConversation(id: conversationID, title: draft.title)
                            dismiss()
                        }
                    }
                    .disabled(chatStore.isReadOnlyMode || draft.title.trimmed.isEmpty)

                    Button("Clear Messages", role: .destructive) {
                        pendingDestructiveAction = .clearMessages
                    }
                    .disabled(chatStore.isReadOnlyMode)
                }

                Section("Runtime") {
                    LabeledContent("Backend", value: chatStore.configuration.backendSummary)
                    LabeledContent("Storage", value: chatStore.storageDescription)
                    LabeledContent("Sync", value: chatStore.syncStatusDescription)
                    LabeledContent("Activation", value: chatStore.activationStatusTitle)
                    LabeledContent("Version", value: chatStore.appVersionDescription)
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
                                text: $draft.systemPrompt,
                                axis: .vertical
                            )
                            .disabled(chatStore.isReadOnlyMode)

                            Button(L10n.tr("prompt_preset.pick")) {
                                isShowingPromptPresetPicker = true
                            }
                            .disabled(chatStore.isReadOnlyMode || chatStore.promptPresets(of: .conversation).isEmpty)

                            Text(systemPromptHint(for: aiConfiguration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if chatStore.isReadOnlyMode == false, draft.isSystemPromptDirty {
                                Button("Save Prompt") {
                                    Task {
                                        await saveSystemPrompt()
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Discard Prompt Changes") {
                                    draft.revertSystemPrompt()
                                }
                                .foregroundStyle(.secondary)
                            }

                            if chatStore.isReadOnlyMode == false, draft.systemPrompt.trimmed.isEmpty == false {
                                Button {
                                    draft.systemPrompt = ""
                                } label: {
                                    Label("Clear Prompt", systemImage: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Memory") {
                        Toggle("Use Global Memory", isOn: globalMemoryBinding(for: conversation.id))
                            .disabled(chatStore.isReadOnlyMode)

                        LabeledContent("Global Items", value: "\(chatStore.globalPinnedMemories.count)")

                        Text("Enable this to let the conversation recall globally pinned memory items in addition to local memory.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Section("Pinned to This Chat") {
                        if conversation.pinnedMemories.isEmpty {
                            Text("No pinned memory yet. Use the message menu to pin important details.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(conversation.pinnedMemories) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(item.text)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    if chatStore.isReadOnlyMode == false {
                                        Button("Remove", role: .destructive) {
                                            pendingDestructiveAction = .removePinnedMemory(item.id)
                                        }
                                        .font(.caption2)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                Section("Danger Zone") {
                    Button("Delete Conversation", role: .destructive) {
                        pendingDestructiveAction = .deleteConversation
                    }
                    .accessibilityIdentifier("conversation.settings.delete")
                }
            }
            .navigationTitle("Manage Chat")
            .navigationBarTitleDisplayMode(.inline)
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
                return "Clear messages?"
            case .deleteConversation:
                return "Delete conversation?"
            case .removePinnedMemory:
                return "Remove pinned memory?"
            }
        }

        var message: String {
            switch self {
            case .clearMessages:
                return "This removes all messages in the conversation."
            case .deleteConversation:
                return "This conversation will be removed from this device."
            case .removePinnedMemory:
                return "This memory will no longer be pinned to this chat."
            }
        }

        var confirmTitle: String {
            switch self {
            case .clearMessages:
                return "Clear Messages"
            case .deleteConversation:
                return "Delete Conversation"
            case .removePinnedMemory:
                return "Remove"
            }
        }
    }
}
#endif
