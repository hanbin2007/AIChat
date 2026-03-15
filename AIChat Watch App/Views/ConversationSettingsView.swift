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
    @State private var promptSaveTask: Task<Void, Never>?
    @State private var isShowingPromptPresetPicker = false

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
                                text: $draftSystemPrompt,
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

                            if chatStore.isReadOnlyMode == false, draftSystemPrompt.trimmed.isEmpty == false {
                                Button {
                                    draftSystemPrompt = ""
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
                                            Task {
                                                await chatStore.removePinnedMemory(id: item.id, from: conversation.id)
                                            }
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
                        Task {
                            await chatStore.deleteConversation(id: conversationID)
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("conversation.settings.delete")
                    .disabled(chatStore.isReadOnlyMode)
                }
            }
            .navigationTitle("Manage Chat")
            .navigationBarTitleDisplayMode(.inline)
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
            .onChange(of: draftSystemPrompt) { _, newValue in
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
                chatStore.setUsesGlobalPinnedMemory(newValue, for: conversationID)
            }
        )
    }
}
#endif
