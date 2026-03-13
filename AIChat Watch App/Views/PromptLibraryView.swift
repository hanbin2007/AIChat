//
//  PromptLibraryView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/12.
//

import SwiftUI

#if os(watchOS)
struct PromptLibraryView: View {
    @EnvironmentObject private var chatStore: ChatStore

    @State private var editingPreset: PromptPreset?
    @State private var isShowingNewPresetEditor = false

    var body: some View {
        ZStack {
            AppBackdropView()

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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L10n.tr("prompt_preset.library.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingNewPresetEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.tr("prompt_preset.create"))
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
