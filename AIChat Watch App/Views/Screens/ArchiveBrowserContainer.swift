//
//  ArchiveBrowserContainer.swift
//  AIChat Watch App
//
//  Read-only archive browser. Loads the conversation, then surfaces
//  every archive segment with title, summary, keywords, and updated
//  timestamp. The "Clear Archive" action is destructive so it gets a
//  confirmation dialog before flushing.
//

import SwiftUI

struct ArchiveBrowserContainer: View {
    @Environment(\.appEnvironment) private var environment

    let id: UUID

    @State private var viewModel: ConversationSettingsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                ArchiveBrowserView(viewModel: vm)
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

struct ArchiveBrowserView: View {
    @Bindable var viewModel: ConversationSettingsViewModel
    @State private var presentingClearConfirmation: Bool = false

    var body: some View {
        Group {
            if viewModel.archiveSegments.isEmpty {
                EmptyStateView(
                    symbol: "archivebox",
                    title: "No archives yet",
                    subtitle: "Archives appear when older parts of this chat are summarized."
                )
            } else {
                List {
                    ForEach(viewModel.archiveSegments) { segment in
                        archiveRow(segment)
                    }
                    Section {
                        Button(role: .destructive) {
                            presentingClearConfirmation = true
                        } label: {
                            Label("Clear Archive", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Archive")
        .confirmationDialog(
            "Clear all archive segments?",
            isPresented: $presentingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                Task { await viewModel.clearArchive() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func archiveRow(_ segment: ConversationArchiveSegment) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(segment.title)
                .font(DS.Typography.listTitle)
            if !segment.summary.isEmpty {
                Text(segment.summary)
                    .font(DS.Typography.listPreview)
                    .foregroundStyle(.secondary)
            }
            if !segment.keywords.isEmpty {
                Text(segment.keywords.joined(separator: " · "))
                    .font(DS.Typography.chip)
                    .foregroundStyle(.tertiary)
            }
            Text(segment.updatedAt, style: .relative)
                .font(DS.Typography.chip)
                .foregroundStyle(.tertiary)
        }
    }
}
