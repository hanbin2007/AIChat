//
//  ConversationListView.swift
//  AIChat Watch App
//
//  Full conversation list — searchable + filter chips + delete
//  confirmation. Reads from `ConversationListViewModel.visibleItems`
//  so all filtering logic lives in the VM.
//

import SwiftUI

struct ConversationListView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var viewModel: ConversationListViewModel?
    @State private var pendingDeleteID: UUID?

    var body: some View {
        Group {
            if let vm = viewModel {
                listBody(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Chats")
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil {
                let vm = ConversationListViewModel(persistence: persistence)
                vm.start()
                viewModel = vm
            }
        }
    }

    private func listBody(_ vm: ConversationListViewModel) -> some View {
        List {
            Section {
                Picker("Filter", selection: Binding(
                    get: { vm.filter },
                    set: { vm.filter = $0 }
                )) {
                    ForEach(ConversationListViewModel.ListFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            if vm.visibleItems.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "bubble.left.and.bubble.right",
                        title: emptyTitle(for: vm.filter),
                        subtitle: emptySubtitle(for: vm.filter)
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(vm.visibleItems) { thread in
                        Button {
                            path.append(Route.conversationDetail(thread.id))
                        } label: {
                            row(thread)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await vm.toggleFavorite(id: thread.id) }
                            } label: {
                                Label(
                                    thread.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: thread.isFavorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeleteID = thread.id
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID {
                    Task { await vm.delete(id: id) }
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteID = nil
            }
        }
    }

    private func row(_ thread: ConversationThread) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                if thread.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(thread.title)
                    .font(DS.Typography.listTitle)
                    .lineLimit(1)
            }
            Text(thread.previewText)
                .font(DS.Typography.listPreview)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func emptyTitle(for filter: ConversationListViewModel.ListFilter) -> String {
        switch filter {
        case .favorites: return "No favorites yet"
        case .recent: return "Nothing recent"
        case .all: return "No conversations yet"
        }
    }

    private func emptySubtitle(for filter: ConversationListViewModel.ListFilter) -> String? {
        switch filter {
        case .favorites: return "Swipe a conversation to favorite it."
        case .recent: return "Conversations from the last 7 days appear here."
        case .all: return nil
        }
    }
}
