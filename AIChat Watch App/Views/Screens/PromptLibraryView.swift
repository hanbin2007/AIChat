//
//  PromptLibraryView.swift
//  AIChat Watch App
//
//  CRUD over `PromptPreset`. Sectioned by kind (chat / transcription).
//  Built-in presets are read-only — tapping shows the editor in
//  read-only mode. Tapping the "+" creates a new preset.
//

import SwiftUI

struct PromptLibraryView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var viewModel: PromptLibraryViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Prompts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    path.append(Route.promptEditor(nil))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Preset")
            }
        }
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil {
                let vm = PromptLibraryViewModel(persistence: persistence)
                viewModel = vm
                await vm.refresh()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: PromptLibraryViewModel) -> some View {
        let resolved = PromptPreset.resolvedLibrary(from: vm.presets)
        if resolved.isEmpty {
            EmptyStateView(
                symbol: "text.book.closed",
                title: "No presets yet",
                subtitle: "Tap + to create your first prompt preset."
            )
        } else {
            List {
                ForEach(PromptPresetKind.allCases) { kind in
                    let group = resolved.filter { $0.kind == kind }
                    if !group.isEmpty {
                        Section(kind.displayName) {
                            ForEach(group) { preset in
                                Button {
                                    path.append(Route.promptEditor(preset.id))
                                } label: {
                                    row(preset)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    if !preset.isBuiltIn {
                                        Button(role: .destructive) {
                                            Task { await vm.delete(id: preset.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ preset: PromptPreset) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(preset.title)
                    .font(DS.Typography.listTitle)
                    .lineLimit(1)
                if preset.isBuiltIn {
                    Text("Built-in")
                        .font(DS.Typography.chip)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
            if !preset.previewText.isEmpty {
                Text(preset.previewText)
                    .font(DS.Typography.listPreview)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
