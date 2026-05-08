//
//  PromptEditorContainer.swift
//  AIChat Watch App
//
//  Bridges a `PromptLibraryViewModel` constructed from the persistence
//  injected through environment with the screen-level
//  `PromptEditorView`. Handles new vs existing preset routing.
//

import SwiftUI

struct PromptEditorContainer: View {
    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    let id: UUID?
    @Binding var path: NavigationPath

    @State private var viewModel: PromptLibraryViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                PromptEditorView(
                    viewModel: vm,
                    presetID: id,
                    onDone: {
                        if !path.isEmpty { path.removeLast() }
                    }
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil {
                let vm = PromptLibraryViewModel(persistence: persistence)
                await vm.refresh()
                viewModel = vm
            }
        }
    }
}

struct PromptEditorView: View {
    let viewModel: PromptLibraryViewModel
    let presetID: UUID?
    let onDone: () -> Void

    @State private var kind: PromptPresetKind = .conversation
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var didLoad = false

    private var existingPreset: PromptPreset? {
        guard let id = presetID else { return nil }
        return PromptPreset.resolvedLibrary(from: viewModel.presets)
            .first(where: { $0.id == id })
    }

    private var isReadOnly: Bool {
        existingPreset?.isBuiltIn ?? false
    }

    var body: some View {
        Form {
            Section("Type") {
                Picker("Type", selection: $kind) {
                    ForEach(PromptPresetKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .disabled(isReadOnly)
            }
            Section("Title") {
                TextField("Title", text: $title)
                    .disabled(isReadOnly)
            }
            Section("Prompt") {
                TextField("Prompt content", text: $content, axis: .vertical)
                    .lineLimit(3...10)
                    .disabled(isReadOnly)
            }
            if isReadOnly {
                Section {
                    Text("Built-in presets are read-only. Create a new one to customize.")
                        .font(DS.Typography.bubbleMeta)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !isReadOnly {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if let existing = existingPreset {
                kind = existing.kind
                title = existing.title
                content = existing.content
            }
        }
    }

    private var navigationTitle: String {
        if isReadOnly { return "View Preset" }
        return existingPreset == nil ? "New Preset" : "Edit Preset"
    }

    private func save() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let preset: PromptPreset
        if let existing = existingPreset {
            preset = existing.updated(kind: kind, title: trimmedTitle, content: trimmedContent)
        } else {
            preset = PromptPreset(kind: kind, title: trimmedTitle, content: trimmedContent)
        }
        await viewModel.upsert(preset)
        onDone()
    }
}
