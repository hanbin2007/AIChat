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

                        Text("Use this to add names, jargon, or style hints for speech recognition.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Requests") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto Retry")
                                .font(.headline)

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
                }
            }
            .navigationTitle("Global Settings")
            .navigationBarTitleDisplayMode(.inline)
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
