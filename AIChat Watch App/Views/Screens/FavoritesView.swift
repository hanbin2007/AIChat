//
//  FavoritesView.swift
//  AIChat Watch App
//
//  Read-only list of starred conversations. Long-press to remove from
//  favorites. Tap to push the detail screen.
//

import SwiftUI

struct FavoritesView: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var path: NavigationPath

    @State private var viewModel: FavoritesViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                if vm.items.isEmpty {
                    EmptyStateView(
                        symbol: "star",
                        title: "No favorites yet",
                        subtitle: "Swipe a conversation to favorite it."
                    )
                } else {
                    List(vm.items) { thread in
                        Button {
                            path.append(Route.conversationDetail(thread.id))
                        } label: {
                            row(thread)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.unfavorite(id: thread.id) }
                            } label: {
                                Label("Unfavorite", systemImage: "star.slash")
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Favorites")
        .task {
            guard let env = environment, let persistence = env.conversations else { return }
            if viewModel == nil {
                let vm = FavoritesViewModel(persistence: persistence)
                vm.start()
                viewModel = vm
            }
        }
    }

    private func row(_ thread: ConversationThread) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(thread.title)
                .font(DS.Typography.listTitle)
                .lineLimit(1)
            Text(thread.previewText)
                .font(DS.Typography.listPreview)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
