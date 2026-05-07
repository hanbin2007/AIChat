#if os(watchOS)
//
//  GlobalSettingsView.swift
//  AIChat Watch App
//
//  Redesigned 2026/4/15 — top-level navigation list with focused detail screens.
//

import SwiftUI

struct GlobalSettingsView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("settings.section.ai")) {
                    NavigationLink {
                        AISettingsDetailView()
                            .environmentObject(chatStore)
                    } label: {
                        SettingsRow(
                            icon: "sparkles",
                            tint: .purple,
                            title: L10n.tr("settings.ai.title"),
                            detail: chatStore.defaultConversationConfiguration.model
                        )
                    }
                }

                Section(L10n.tr("settings.section.voice")) {
                    NavigationLink {
                        VoiceSettingsDetailView()
                            .environmentObject(chatStore)
                    } label: {
                        SettingsRow(
                            icon: "waveform",
                            tint: .orange,
                            title: L10n.tr("settings.voice.title"),
                            detail: chatStore.selectedTranscriptionModel
                        )
                    }
                }

                Section(L10n.tr("settings.section.behavior")) {
                    NavigationLink {
                        BehaviorSettingsDetailView()
                            .environmentObject(chatStore)
                    } label: {
                        SettingsRow(
                            icon: "slider.horizontal.3",
                            tint: .blue,
                            title: L10n.tr("settings.behavior.title"),
                            detail: chatStore.isGlobalAutoScrollEnabled
                                ? L10n.tr("common.on")
                                : L10n.tr("common.off")
                        )
                    }
                }

                Section(L10n.tr("settings.section.memory")) {
                    NavigationLink {
                        PinnedMemorySettingsDetailView()
                            .environmentObject(chatStore)
                    } label: {
                        SettingsRow(
                            icon: "pin.fill",
                            tint: .pink,
                            title: L10n.tr("settings.memory.title"),
                            detail: L10n.format(
                                "settings.memory.count",
                                chatStore.globalPinnedMemories.count
                            )
                        )
                    }
                }

                Section("授权与密钥") {
                    NavigationLink {
                        KeyStatusDetailView()
                            .environmentObject(chatStore)
                    } label: {
                        SettingsRow(
                            icon: "key.fill",
                            tint: .green,
                            title: "密钥与授权",
                            detail: keyStatusSummary
                        )
                    }
                }

                Section(L10n.tr("settings.section.about")) {
                    LabeledContent(
                        L10n.tr("settings.about.version"),
                        value: chatStore.appVersionDescription
                    )
                }
            }
            .navigationTitle(L10n.tr("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var keyStatusSummary: String {
        // Match the row's `detail` line to whatever the user is most
        // likely to act on first. Order: missing key → unactivated →
        // active license. Mirrors the row used above the activation
        // card on the conversation list.
        if chatStore.configuration.isAIConfigured == false {
            return "未配置"
        }
        if chatStore.activationState == nil {
            return "待激活"
        }
        return chatStore.activationStatusTitle
    }
}

// MARK: - Key & Activation Detail

private struct KeyStatusDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingActivationCenter = false
    @State private var isShowingRelayDetail = false

    var body: some View {
        List {
            Section("后端") {
                LabeledContent("模式", value: backendModeText)
                LabeledContent("AI 配置", value: chatStore.configuration.isAIConfigured ? "已配置" : "未配置")
                if chatStore.configuration.isAIConfigured == false {
                    Text(chatStore.configuration.configurationMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if chatStore.configuration.backendMode == .relay {
                Section("Relay") {
                    LabeledContent("Server", value: relayHostText)
                    LabeledContent("连接", value: relayStatusText)
                    Button {
                        isShowingRelayDetail = true
                    } label: {
                        Label("查看连接详情", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }

            Section("激活") {
                LabeledContent("状态", value: chatStore.activationStatusTitle)
                if let state = chatStore.activationState {
                    LabeledContent(
                        "生效",
                        value: state.license.validFrom.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent(
                        "到期",
                        value: state.license.validUntil?
                            .formatted(date: .abbreviated, time: .shortened) ?? "长期"
                    )
                    LabeledContent("已用消息", value: "\(state.usedMessageCount)")
                    if let limit = state.license.messageLimit {
                        LabeledContent("总额度", value: "\(limit)")
                    }
                }

                Text(chatStore.activationStatusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    isShowingActivationCenter = true
                } label: {
                    Label(
                        chatStore.activationState == nil ? "立即激活" : "管理授权",
                        systemImage: chatStore.activationState == nil ? "key.fill" : "checkmark.seal.fill"
                    )
                }
            }

            Section("设备") {
                LabeledContent("设备码", value: chatStore.deviceIdentity.displayToken)
            }
        }
        .navigationTitle("密钥与授权")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingActivationCenter) {
            ActivationCenterView()
                .environmentObject(chatStore)
        }
    }

    private var backendModeText: String {
        switch chatStore.configuration.backendMode {
        case .direct:
            return "Direct"
        case .relay:
            return "Relay"
        }
    }

    private var relayHostText: String {
        guard let url = chatStore.configuration.relayBaseURL else {
            return "—"
        }
        if let scheme = url.scheme, let host = url.host() {
            return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        }
        return url.absoluteString
    }

    private var relayStatusText: String {
        switch chatStore.relayConnectionStatus {
        case .unknown:
            return "未知"
        case .connecting:
            return "连接中"
        case .online:
            return "在线"
        case .offline:
            return "离线"
        }
    }
}

// MARK: - Row Component

private struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.20))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                if let detail, detail.isEmpty == false {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AI Detail

private struct AISettingsDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingPresetPicker = false

    var body: some View {
        List {
            Section {
                Picker(L10n.tr("settings.ai.default_model"), selection: modelBinding) {
                    ForEach(chatStore.availableModelOptions()) { option in
                        Text(option.title).tag(option.id)
                    }
                }

                Picker(L10n.tr("settings.ai.thinking"), selection: thinkingBinding) {
                    ForEach(chatStore.availableDefaultThinkingIntensities()) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
            }

            Section {
                TextField(
                    L10n.tr("settings.ai.system_prompt.placeholder"),
                    text: systemPromptBinding,
                    axis: .vertical
                )

                Button(L10n.tr("prompt_preset.pick")) {
                    isShowingPresetPicker = true
                }
                .disabled(chatStore.promptPresets(of: .conversation).isEmpty)
            } header: {
                Text(L10n.tr("settings.ai.system_prompt"))
            } footer: {
                Text(L10n.tr("settings.ai.system_prompt.footnote"))
            }
        }
        .navigationTitle(L10n.tr("settings.ai.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPresetPicker) {
            PromptPresetPickerView(
                kind: .conversation,
                title: L10n.tr("prompt_preset.library.title"),
                onSelect: { preset in
                    chatStore.updateDefaultConversationSystemPrompt(preset.content)
                }
            )
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { chatStore.defaultConversationConfiguration.model },
            set: { chatStore.updateDefaultConversationModel($0) }
        )
    }

    private var thinkingBinding: Binding<AIThinkingIntensity> {
        Binding(
            get: { chatStore.defaultConversationConfiguration.thinkingIntensity },
            set: { chatStore.updateDefaultConversationThinkingIntensity($0) }
        )
    }

    private var systemPromptBinding: Binding<String> {
        Binding(
            get: { chatStore.defaultConversationSystemPrompt },
            set: { chatStore.updateDefaultConversationSystemPrompt($0) }
        )
    }
}

// MARK: - Voice Detail

private struct VoiceSettingsDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isShowingPresetPicker = false

    var body: some View {
        List {
            Section {
                Picker(L10n.tr("settings.voice.model"), selection: modelBinding) {
                    ForEach(chatStore.availableTranscriptionModelOptions()) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section {
                Toggle(L10n.tr("settings.voice.include_context"), isOn: contextBinding)
            } footer: {
                Text(L10n.tr("settings.voice.include_context.footnote"))
            }

            Section {
                TextField(
                    L10n.tr("settings.voice.custom_prompt.placeholder"),
                    text: promptBinding,
                    axis: .vertical
                )

                Button(L10n.tr("prompt_preset.pick")) {
                    isShowingPresetPicker = true
                }
                .disabled(chatStore.promptPresets(of: .transcription).isEmpty)
            } header: {
                Text(L10n.tr("settings.voice.custom_prompt"))
            } footer: {
                Text(L10n.tr("settings.voice.custom_prompt.footnote"))
            }
        }
        .navigationTitle(L10n.tr("settings.voice.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPresetPicker) {
            PromptPresetPickerView(
                kind: .transcription,
                title: L10n.tr("prompt_preset.library.title"),
                onSelect: { preset in
                    chatStore.updateTranscriptionCustomPrompt(preset.content)
                }
            )
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { chatStore.selectedTranscriptionModel },
            set: { chatStore.updateTranscriptionModel($0) }
        )
    }

    private var contextBinding: Binding<Bool> {
        Binding(
            get: { chatStore.isTranscriptionContextEnabled },
            set: { chatStore.updateTranscriptionIncludesContext($0) }
        )
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { chatStore.selectedTranscriptionCustomPrompt },
            set: { chatStore.updateTranscriptionCustomPrompt($0) }
        )
    }
}

// MARK: - Behavior Detail

private struct BehaviorSettingsDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        List {
            Section {
                Toggle(L10n.tr("settings.behavior.auto_scroll"), isOn: autoScrollBinding)
            } footer: {
                Text(L10n.tr("settings.behavior.auto_scroll.footnote"))
            }

            Section {
                Stepper(value: retryBinding, in: retryRange) {
                    HStack {
                        Text(L10n.tr("settings.behavior.retry_limit"))
                        Spacer()
                        Text("\(chatStore.sendFailureRetryLimit)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(L10n.format("settings.retry.watch", chatStore.sendFailureRetryLimit))
            }
        }
        .navigationTitle(L10n.tr("settings.behavior.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var autoScrollBinding: Binding<Bool> {
        Binding(
            get: { chatStore.isGlobalAutoScrollEnabled },
            set: { chatStore.updateGlobalAutoScrollEnabled($0) }
        )
    }

    private var retryBinding: Binding<Int> {
        Binding(
            get: { chatStore.sendFailureRetryLimit },
            set: { chatStore.updateSendFailureRetryLimit($0) }
        )
    }

    private var retryRange: ClosedRange<Int> {
        ChatStore.minimumSendFailureRetryLimit...ChatStore.maximumSendFailureRetryLimit
    }
}

// MARK: - Pinned Memory Detail

private struct PinnedMemorySettingsDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        List {
            if chatStore.globalPinnedMemories.isEmpty {
                Section {
                    Text(L10n.tr("settings.memory.empty"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Section {
                    ForEach(chatStore.globalPinnedMemories) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(
                                L10n.format(
                                    "settings.memory.updated",
                                    item.updatedAt.formatted(date: .abbreviated, time: .shortened)
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if chatStore.isReadOnlyMode == false {
                                Button(role: .destructive) {
                                    Task {
                                        await chatStore.removeGlobalPinnedMemory(id: item.id)
                                    }
                                } label: {
                                    Label(
                                        L10n.tr("settings.memory.remove"),
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr("settings.memory.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
