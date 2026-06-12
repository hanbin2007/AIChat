#if COMPANION_APP
//
//  CompanionGlobalSettingsView.swift
//  AIChat
//
//  Created by Codex on 2026/3/9.
//

import SwiftUI

struct CompanionGlobalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingConversationPresetPicker = false
    @State private var isShowingTranscriptionPresetPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("settings.section.new_conversation_defaults")) {
                    Picker(L10n.tr("settings.ai.default_model"), selection: defaultModelBinding()) {
                        ForEach(chatStore.availableModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker(L10n.tr("settings.ai.thinking"), selection: defaultThinkingBinding()) {
                        ForEach(chatStore.availableDefaultThinkingIntensities()) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("settings.ai.system_prompt"))
                            .font(.headline)

                        TextField(
                            L10n.tr("settings.ai.system_prompt.placeholder"),
                            text: defaultSystemPromptBinding(),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(L10n.tr("prompt_preset.pick")) {
                            isShowingConversationPresetPicker = true
                        }
                        .disabled(chatStore.promptPresets(of: .conversation).isEmpty)

                        Text(L10n.tr("settings.ai.system_prompt.footnote"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L10n.tr("settings.voice.title")) {
                    Picker(L10n.tr("settings.voice.model"), selection: transcriptionModelBinding()) {
                        ForEach(chatStore.availableTranscriptionModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Toggle(L10n.tr("settings.voice.include_context"), isOn: transcriptionContextBinding())

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("settings.voice.custom_prompt"))
                            .font(.headline)

                        TextField(
                            L10n.tr("settings.voice.custom_prompt.placeholder"),
                            text: transcriptionPromptBinding(),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(L10n.tr("prompt_preset.pick")) {
                            isShowingTranscriptionPresetPicker = true
                        }
                        .disabled(chatStore.promptPresets(of: .transcription).isEmpty)

                        Text(L10n.tr("settings.voice.custom_prompt.footnote"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L10n.tr("settings.section.behavior")) {
                    Toggle(L10n.tr("settings.behavior.auto_scroll"), isOn: globalAutoScrollBinding())
                        .accessibilityIdentifier("companion.settings.auto-scroll")

                    Text(L10n.tr("settings.behavior.auto_scroll.footnote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("settings.section.requests")) {
                    Stepper(
                        value: sendFailureRetryLimitBinding(),
                        in: ChatStore.minimumSendFailureRetryLimit...ChatStore.maximumSendFailureRetryLimit
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("settings.behavior.retry_limit"))
                            Text(L10n.format("settings.retry.ios", chatStore.sendFailureRetryLimit))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L10n.tr("settings.memory.global_title")) {
                    if chatStore.globalPinnedMemories.isEmpty {
                        Text(L10n.tr("settings.memory.empty"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chatStore.globalPinnedMemories) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.text)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                if chatStore.isReadOnlyMode == false {
                                    Button(L10n.tr("settings.memory.delete_global"), role: .destructive) {
                                        Task {
                                            await chatStore.removeGlobalPinnedMemory(id: item.id)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(L10n.tr("settings.about.title")) {
                    LabeledContent(L10n.tr("settings.about.version"), value: chatStore.appVersionDescription)
                }
            }
            .navigationTitle(L10n.tr("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingConversationPresetPicker) {
                PromptPresetPickerView(
                    kind: .conversation,
                    title: L10n.tr("prompt_preset.library.title"),
                    onSelect: { preset in
                        chatStore.updateDefaultConversationSystemPrompt(preset.content)
                    }
                )
            }
            .sheet(isPresented: $isShowingTranscriptionPresetPicker) {
                PromptPresetPickerView(
                    kind: .transcription,
                    title: L10n.tr("prompt_preset.library.title"),
                    onSelect: { preset in
                        chatStore.updateTranscriptionCustomPrompt(preset.content)
                    }
                )
            }
        }
        .accessibilityIdentifier("companion.global-settings")
    }

    private func defaultModelBinding() -> Binding<String> {
        Binding(
            get: {
                chatStore.defaultConversationConfiguration.model
            },
            set: { newValue in
                chatStore.updateDefaultConversationModel(newValue)
            }
        )
    }

    private func defaultThinkingBinding() -> Binding<AIThinkingIntensity> {
        Binding(
            get: {
                chatStore.defaultConversationConfiguration.thinkingIntensity
            },
            set: { newValue in
                chatStore.updateDefaultConversationThinkingIntensity(newValue)
            }
        )
    }

    private func defaultSystemPromptBinding() -> Binding<String> {
        Binding(
            get: {
                chatStore.defaultConversationSystemPrompt
            },
            set: { newValue in
                chatStore.updateDefaultConversationSystemPrompt(newValue)
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

    private func transcriptionPromptBinding() -> Binding<String> {
        Binding(
            get: {
                chatStore.selectedTranscriptionCustomPrompt
            },
            set: { newValue in
                chatStore.updateTranscriptionCustomPrompt(newValue)
            }
        )
    }

    private func transcriptionContextBinding() -> Binding<Bool> {
        Binding(
            get: {
                chatStore.isTranscriptionContextEnabled
            },
            set: { newValue in
                chatStore.updateTranscriptionIncludesContext(newValue)
            }
        )
    }

    private func globalAutoScrollBinding() -> Binding<Bool> {
        Binding(
            get: {
                chatStore.isGlobalAutoScrollEnabled
            },
            set: { newValue in
                chatStore.updateGlobalAutoScrollEnabled(newValue)
            }
        )
    }

    private func sendFailureRetryLimitBinding() -> Binding<Int> {
        Binding(
            get: {
                chatStore.sendFailureRetryLimit
            },
            set: { newValue in
                chatStore.updateSendFailureRetryLimit(newValue)
            }
        )
    }
}
#endif
