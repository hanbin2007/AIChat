//
//  ConversationSettingsView.swift
//  AIChat Watch App
//
//  Per-conversation settings screen with five sections:
//    1. Title editor
//    2. AI configuration (model / thinking / system prompt)
//    3. Tools (Google Search / Code Execution)
//    4. Memory (memory items, pinned items, global memory toggle)
//    5. Archive browser link + danger zone
//
//  Heavy CRUD is delegated to `ConversationSettingsViewModel`. The
//  view only owns local edit buffers (title text, prompt text) so
//  changes are atomic.
//

import SwiftUI

struct ConversationSettingsView: View {
    @Bindable var viewModel: ConversationSettingsViewModel
    @Binding var path: NavigationPath

    @State private var titleDraft: String = ""
    @State private var systemPromptDraft: String = ""
    @State private var didLoad = false

    private var configuration: ConversationAIConfiguration {
        viewModel.conversation.aiConfiguration
            ?? ConversationAIConfiguration(model: "gemini-3-flash-preview")
    }

    var body: some View {
        Form {
            titleSection
            aiSection
            toolsSection
            memorySection
            archiveSection
        }
        .navigationTitle("Settings")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            titleDraft = viewModel.conversation.title
            systemPromptDraft = configuration.customSystemPrompt ?? ""
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        Section("Title") {
            TextField("Title", text: $titleDraft)
            Button("Save Title") {
                Task { await viewModel.setTitle(titleDraft) }
            }
            .disabled(titleDraft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section("AI") {
            Picker("Model", selection: Binding(
                get: { configuration.model },
                set: { newValue in Task { await viewModel.setModel(newValue) } }
            )) {
                ForEach(AIModelCatalog.quickOptions(defaultModel: configuration.model), id: \.id) { option in
                    Text(option.title).tag(option.id)
                }
            }
            Picker("Thinking", selection: Binding(
                get: { configuration.thinkingIntensity },
                set: { newValue in Task { await viewModel.setThinkingIntensity(newValue) } }
            )) {
                ForEach(AIModelCatalog.availableThinkingIntensities(for: configuration.model)) { intensity in
                    Text(intensity.displayName).tag(intensity)
                }
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("System Prompt")
                    .font(DS.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                TextField("Use built-in prompt", text: $systemPromptDraft, axis: .vertical)
                    .lineLimit(2...5)
                Button("Save Prompt") {
                    Task { await viewModel.setCustomSystemPrompt(systemPromptDraft) }
                }
                .font(DS.Typography.bubbleMeta)
            }
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        Section("Tools") {
            Toggle("Google Search", isOn: Binding(
                get: { configuration.usesGoogleSearch },
                set: { newValue in Task { await viewModel.setUsesGoogleSearch(newValue) } }
            ))
            Toggle("Code Execution", isOn: Binding(
                get: { configuration.usesCodeExecution },
                set: { newValue in Task { await viewModel.setUsesCodeExecution(newValue) } }
            ))
        }
    }

    // MARK: - Memory

    private var memorySection: some View {
        Section("Memory") {
            Toggle("Use Global Memory", isOn: Binding(
                get: { configuration.usesGlobalPinnedMemory },
                set: { newValue in Task { await viewModel.setUsesGlobalPinnedMemory(newValue) } }
            ))
            Button {
                path.append(Route.memoryEditor(viewModel.conversation.id))
            } label: {
                HStack {
                    Label("Memory Items", systemImage: "brain")
                    Spacer()
                    Text("\(viewModel.conversation.memoryItems.count)")
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                path.append(Route.globalPinnedMemory)
            } label: {
                Label("Global Pinned Memory", systemImage: "pin")
            }
        }
    }

    // MARK: - Archive

    private var archiveSection: some View {
        Section {
            Button {
                path.append(Route.archiveBrowser(viewModel.conversation.id))
            } label: {
                HStack {
                    Label("Archive", systemImage: "archivebox")
                    Spacer()
                    Text("\(viewModel.conversation.archiveSegments.count)")
                        .foregroundStyle(.secondary)
                }
            }
            if let focus = viewModel.conversation.focusState {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Focus")
                        .font(DS.Typography.sectionHeader)
                        .foregroundStyle(.secondary)
                    Text(focus.title)
                        .font(DS.Typography.listTitle)
                    if !focus.focusNote.isEmpty {
                        Text(focus.focusNote)
                            .font(DS.Typography.bubbleMeta)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
