#if COMPANION_APP
//
//  CompanionPromptLibraryView.swift
//  AIChat
//
//  Created by Codex on 2026/3/12.
//

import SwiftUI

struct CompanionPromptLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    @State private var editingPreset: PromptPreset?
    @State private var isShowingNewPresetEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(PromptPresetKind.allCases) { kind in
                    Section(kind.displayName) {
                        let presets = chatStore.promptPresets(of: kind)
                        if presets.isEmpty {
                            Text(L10n.tr("prompt_preset.empty.section"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(presets) { preset in
                                Button {
                                    editingPreset = preset
                                } label: {
                                    PromptPresetRowView(preset: preset)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if preset.isBuiltIn == false {
                                        Button(role: .destructive) {
                                            Task {
                                                await chatStore.deletePromptPreset(id: preset.id)
                                            }
                                        } label: {
                                            Label(L10n.tr("prompt_preset.delete"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppBackdropView())
            .navigationTitle(L10n.tr("prompt_preset.library.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingNewPresetEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.tr("prompt_preset.create"))
                }
            }
        }
        .sheet(item: $editingPreset) { preset in
            PromptPresetEditorView(preset: preset)
        }
        .sheet(isPresented: $isShowingNewPresetEditor) {
            PromptPresetEditorView(initialKind: .conversation)
        }
    }
}
#endif
