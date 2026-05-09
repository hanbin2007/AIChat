//
//  GlobalPinnedMemoryView.swift
//  AIChat Watch App
//
//  CRUD over global pinned memory items. Each row swipes to delete.
//  Add new items via the inline editor at the top.
//

import SwiftUI

struct GlobalPinnedMemoryView: View {
    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: GlobalPinnedMemoryViewModel?
    @State private var newItemText: String = ""

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Global Memory")
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil {
                let vm = GlobalPinnedMemoryViewModel(persistence: persistence)
                viewModel = vm
                await vm.refresh()
            }
        }
    }

    @ViewBuilder
    private func content(_ vm: GlobalPinnedMemoryViewModel) -> some View {
        Form {
            Section("Add Memory") {
                TextField("New global pinned memory", text: $newItemText, axis: .vertical)
                    .lineLimit(2...4)
                Button("Add") {
                    let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task {
                        await vm.add(text: trimmed)
                        newItemText = ""
                    }
                }
                .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Pinned Globally") {
                if vm.items.isEmpty {
                    Text("No global pinned memory yet.")
                        .font(DS.Typography.bubbleMeta)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.items) { item in
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(item.text)
                                .font(DS.Typography.bubbleBody)
                            if !item.keywords.isEmpty {
                                Text(item.keywords.joined(separator: " · "))
                                    .font(DS.Typography.chip)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.remove(id: item.id) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}
