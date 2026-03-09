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

    var body: some View {
        NavigationStack {
            Form {
                Section("新建会话默认参数") {
                    Picker("默认模型", selection: defaultModelBinding()) {
                        ForEach(chatStore.availableModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker("默认 Thinking", selection: defaultThinkingBinding()) {
                        ForEach(chatStore.availableDefaultThinkingIntensities()) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("默认系统提示词")
                            .font(.headline)

                        TextField(
                            "留空则使用内置系统提示词",
                            text: defaultSystemPromptBinding(),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)

                        Text("新建对话时会自动带上这里的系统提示词；留空时继续使用应用内置提示词。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("语音识别") {
                    Picker("语音识别模型", selection: transcriptionModelBinding()) {
                        ForEach(chatStore.availableTranscriptionModelOptions()) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Toggle("包含上下文", isOn: transcriptionContextBinding())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义提示词")
                            .font(.headline)

                        TextField(
                            "例如人名、术语、品牌名",
                            text: transcriptionPromptBinding(),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)

                        Text("会附加到语音识别提示词里，用来帮助识别专有名词、口头习惯或领域术语。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("请求") {
                    Stepper(
                        value: sendFailureRetryLimitBinding(),
                        in: ChatStore.minimumSendFailureRetryLimit...ChatStore.maximumSendFailureRetryLimit
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("请求失败自动重试")
                            Text("发送和语音转录失败后最多重试 \(chatStore.sendFailureRetryLimit) 次，最高 10 次。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("全局设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
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
