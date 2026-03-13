//
//  PromptPresetSupportViews.swift
//  AIChat
//
//  Created by Codex on 2026/3/12.
//

import SwiftUI

struct PromptPresetRowView: View {
    let preset: PromptPreset
    var showsKind: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(preset.title)
                    .font(.headline)
                    .lineLimit(2)

                if preset.isBuiltIn {
                    Text(L10n.tr("prompt_preset.builtin.badge"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.yellow.opacity(0.14))
                        )
                }

                Spacer(minLength: 0)
            }

            if showsKind {
                Text(preset.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text(preset.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PromptPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    private let preset: PromptPreset?
    private let isReadOnly: Bool

    @State private var selectedKind: PromptPresetKind
    @State private var title: String
    @State private var content: String

    init(
        preset: PromptPreset? = nil,
        initialKind: PromptPresetKind = .conversation
    ) {
        self.preset = preset
        self.isReadOnly = preset?.isBuiltIn == true
        _selectedKind = State(initialValue: preset?.kind ?? initialKind)
        _title = State(initialValue: preset?.title ?? "")
        _content = State(initialValue: preset?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("common.close")) {
                            dismiss()
                        }
                    }

                    if isReadOnly == false {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.tr("common.save")) {
                                savePreset()
                            }
                            .disabled(title.trimmed.isEmpty || content.trimmed.isEmpty)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        #if os(iOS)
        Form {
            editorSections
        }
        #else
        List {
            editorSections
        }
        #endif
    }

    @ViewBuilder
    private var editorSections: some View {
        Section(L10n.tr("prompt_preset.section.details")) {
            Picker(L10n.tr("prompt_preset.field.kind"), selection: $selectedKind) {
                ForEach(PromptPresetKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .disabled(isReadOnly)

            TextField(
                L10n.tr("prompt_preset.field.title"),
                text: $title
            )
            .disabled(isReadOnly)

            TextField(
                L10n.tr("prompt_preset.field.content"),
                text: $content,
                axis: .vertical
            )
            .lineLimit(6...12)
            .disabled(isReadOnly)
        }

        if isReadOnly {
            Section {
                Text(L10n.tr("prompt_preset.builtin.read_only"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var navigationTitle: String {
        if let preset {
            return preset.isBuiltIn ?
                L10n.tr("prompt_preset.editor.title.view") :
                L10n.tr("prompt_preset.editor.title.edit")
        }

        return L10n.tr("prompt_preset.editor.title.new")
    }

    private func savePreset() {
        let normalizedTitle = title.trimmed
        let normalizedContent = content.trimmed
        guard normalizedTitle.isEmpty == false,
              normalizedContent.isEmpty == false
        else {
            return
        }

        Task {
            if let preset {
                await chatStore.updatePromptPreset(
                    id: preset.id,
                    kind: selectedKind,
                    title: normalizedTitle,
                    content: normalizedContent
                )
            } else {
                await chatStore.createPromptPreset(
                    kind: selectedKind,
                    title: normalizedTitle,
                    content: normalizedContent
                )
            }

            dismiss()
        }
    }
}

struct PromptPresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    let kind: PromptPresetKind
    let title: String
    let onSelect: (PromptPreset) -> Void

    var body: some View {
        NavigationStack {
            List {
                let presets = chatStore.promptPresets(of: kind)
                if presets.isEmpty {
                    Text(L10n.tr("prompt_preset.empty.selection"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(presets) { preset in
                        Button {
                            onSelect(preset)
                            dismiss()
                        } label: {
                            PromptPresetRowView(preset: preset, showsKind: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
