#if os(watchOS)
//
//  GlobalSettingsView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/9.
//

import SwiftUI

struct GlobalSettingsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingConversationPresetPicker = false
    @State private var isShowingTranscriptionPresetPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("New Chats") {
                    Picker("Model", selection: defaultModelBinding()) {
                        ForEach(chatStore.availableModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker("Thinking", selection: defaultThinkingBinding()) {
                        ForEach(chatStore.availableDefaultThinkingIntensities()) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default System Prompt")
                            .font(.headline)

                        TextField(
                            "Use the built-in prompt",
                            text: defaultSystemPromptBinding(),
                            axis: .vertical
                        )

                        Button(L10n.tr("prompt_preset.pick")) {
                            isShowingConversationPresetPicker = true
                        }
                        .disabled(chatStore.promptPresets(of: .conversation).isEmpty)

                        Text("This prompt is applied to newly created conversations. Leave it empty to keep using the built-in system prompt.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Voice Recognition") {
                    Picker("Voice Model", selection: transcriptionModelBinding()) {
                        ForEach(chatStore.availableTranscriptionModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Toggle("Include Context", isOn: transcriptionContextBinding())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Prompt")
                            .font(.headline)

                        TextField(
                            "Optional transcription hint",
                            text: transcriptionPromptBinding(),
                            axis: .vertical
                        )

                        Button(L10n.tr("prompt_preset.pick")) {
                            isShowingTranscriptionPresetPicker = true
                        }
                        .disabled(chatStore.promptPresets(of: .transcription).isEmpty)

                        Text("Use this to add names, jargon, or style hints for speech recognition.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Requests") {
                    Toggle("Auto Scroll", isOn: globalAutoScrollBinding())

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto Retry")
                                .font(.headline)

                            Text(L10n.format("settings.retry.watch", chatStore.sendFailureRetryLimit))
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

                    Text("控制所有对话在收到新回复时是否自动跟随到底部。关闭后保留手动滚动位置。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Global Memory") {
                    if chatStore.globalPinnedMemories.isEmpty {
                        Text("No global pinned memory yet. Pin a message globally to make it reusable across conversations.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(chatStore.globalPinnedMemories) { item in
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
                                            await chatStore.removeGlobalPinnedMemory(id: item.id)
                                        }
                                    }
                                    .font(.caption2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: chatStore.appVersionDescription)
                }
            }
            .navigationTitle("Global Settings")
            .navigationBarTitleDisplayMode(.inline)
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
