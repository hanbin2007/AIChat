//
//  GlobalSettingsView.swift
//  AIChat Watch App
//
//  App-wide settings — defaults for new conversations, voice
//  transcription, and behavior toggles. Persists through
//  `SettingsService` which is a `@Published` ObservableObject; the
//  `GlobalSettingsViewModel` shadow-copies the state for the view.
//

import SwiftUI

struct GlobalSettingsView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var viewModel: GlobalSettingsViewModel?
    @State private var systemPromptDraft: String = ""
    @State private var customPromptDraft: String = ""
    @State private var didLoad = false

    var body: some View {
        Group {
            if let vm = viewModel {
                form(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Settings")
        .task {
            if viewModel == nil, let env = environment {
                viewModel = GlobalSettingsViewModel(settings: env.settingsService)
            }
        }
    }

    @ViewBuilder
    private func form(_ vm: GlobalSettingsViewModel) -> some View {
        Form {
            aiSection(vm)
            voiceSection(vm)
            behaviorSection(vm)
            memorySection
            aboutSection
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            systemPromptDraft = vm.defaultConversationConfiguration.customSystemPrompt ?? ""
            customPromptDraft = vm.transcriptionCustomPrompt
        }
    }

    // MARK: - Sections

    private func aiSection(_ vm: GlobalSettingsViewModel) -> some View {
        Section("AI") {
            Picker("Default Model", selection: Binding(
                get: { vm.defaultConversationConfiguration.model },
                set: { vm.updateDefaultConversationModel($0) }
            )) {
                ForEach(AIModelCatalog.quickOptions(defaultModel: vm.defaultConversationConfiguration.model), id: \.id) { option in
                    Text(option.title).tag(option.id)
                }
            }
            Picker("Thinking", selection: Binding(
                get: { vm.defaultConversationConfiguration.thinkingIntensity },
                set: { vm.updateDefaultThinkingIntensity($0) }
            )) {
                ForEach(AIModelCatalog.availableThinkingIntensities(for: vm.defaultConversationConfiguration.model)) { intensity in
                    Text(intensity.displayName).tag(intensity)
                }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Default System Prompt")
                    .font(DS.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                TextField("Use built-in prompt", text: $systemPromptDraft, axis: .vertical)
                    .lineLimit(2...5)
                Button("Save Prompt") {
                    vm.updateDefaultSystemPrompt(systemPromptDraft)
                }
                .font(DS.Typography.bubbleMeta)
            }
        }
    }

    private func voiceSection(_ vm: GlobalSettingsViewModel) -> some View {
        Section("Voice") {
            Picker("Voice Model", selection: Binding(
                get: { vm.transcriptionModel },
                set: { vm.updateTranscriptionModel($0) }
            )) {
                ForEach(AITranscriptionModelCatalog.options(defaultModel: vm.transcriptionModel), id: \.id) { option in
                    Text(option.title).tag(option.id)
                }
            }
            Toggle("Include Context", isOn: Binding(
                get: { vm.transcriptionIncludesContext },
                set: { vm.updateTranscriptionIncludesContext($0) }
            ))
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Custom Prompt")
                    .font(DS.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                TextField("Optional vocabulary", text: $customPromptDraft, axis: .vertical)
                    .lineLimit(2...4)
                Button("Save Prompt") {
                    vm.updateTranscriptionCustomPrompt(customPromptDraft)
                }
                .font(DS.Typography.bubbleMeta)
            }
        }
    }

    private func behaviorSection(_ vm: GlobalSettingsViewModel) -> some View {
        Section("Behavior") {
            Toggle("Auto-follow Bottom", isOn: Binding(
                get: { vm.isGlobalAutoScrollEnabled },
                set: { vm.updateGlobalAutoScroll($0) }
            ))
            Stepper(
                value: Binding(
                    get: { vm.sendFailureRetryLimit },
                    set: { vm.updateSendFailureRetryLimit($0) }
                ),
                in: SettingsService.minimumSendFailureRetryLimit...SettingsService.maximumSendFailureRetryLimit
            ) {
                HStack {
                    Text("Retry Attempts")
                    Spacer()
                    Text("\(vm.sendFailureRetryLimit)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var memorySection: some View {
        Section("Memory") {
            Button {
                path.append(Route.globalPinnedMemory)
            } label: {
                Label("Global Pinned Memory", systemImage: "pin")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.appVersionDescription)
                    .foregroundStyle(.secondary)
            }
            if let env = environment {
                HStack {
                    Text("Relay")
                    Spacer()
                    Text(env.connectionMonitor.description)
                        .foregroundStyle(.secondary)
                        .font(DS.Typography.bubbleMeta)
                }
            }
        }
    }
}
