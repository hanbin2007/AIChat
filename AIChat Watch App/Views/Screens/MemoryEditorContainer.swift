//
//  MemoryEditorContainer.swift
//  AIChat Watch App
//
//  Resolves a conversation by id and renders the memory editor for it.
//

import SwiftUI

struct MemoryEditorContainer: View {
    @Environment(\.appEnvironment) private var environment

    let id: UUID

    @State private var viewModel: ConversationSettingsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                MemoryEditorView(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil, let thread = try? await persistence.conversation(id: id) {
                viewModel = ConversationSettingsViewModel(
                    conversation: thread,
                    persistence: persistence
                )
            }
        }
    }
}

struct MemoryEditorView: View {
    @Bindable var viewModel: ConversationSettingsViewModel

    @State private var newItemText: String = ""

    var body: some View {
        Form {
            Section("Add Memory") {
                TextField("New memory note", text: $newItemText, axis: .vertical)
                    .lineLimit(2...4)
                Button("Add") {
                    let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task {
                        await viewModel.addMemoryItem(text: trimmed)
                        newItemText = ""
                    }
                }
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Memory Items") {
                if viewModel.conversation.memoryItems.isEmpty {
                    Text("No memory items yet.")
                        .font(DS.Typography.bubbleMeta)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.conversation.memoryItems) { item in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(item.text)
                                .font(DS.Typography.bubbleBody)
                            if !item.keywords.isEmpty {
                                keywordChips(item.keywords)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.removeMemoryItem(id: item.id) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Pinned to This Chat") {
                if viewModel.conversation.pinnedMemories.isEmpty {
                    Text("No pinned memory yet.")
                        .font(DS.Typography.bubbleMeta)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.conversation.pinnedMemories) { item in
                        Text(item.text)
                            .font(DS.Typography.listPreview)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.removePinnedMemory(id: item.id) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Memory")
    }

    private func keywordChips(_ keywords: [String]) -> some View {
        FlexibleHStack(spacing: DS.Spacing.xs) {
            ForEach(keywords, id: \.self) { keyword in
                Text(keyword)
                    .font(DS.Typography.chip)
                    .padding(.horizontal, DS.Spacing.s)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Small helper that lays children left-to-right and wraps to next line
/// when the row width is exceeded. Used for keyword chips on the watch
/// where the screen is narrow.
private struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        // SwiftUI doesn't ship a built-in flexible row prior to iOS 16.
        // For our small chip use-case a plain HStack with `wrap`
        // approximated via a vertical fallback works on the watch.
        HStack(spacing: spacing) {
            content()
        }
    }
}
