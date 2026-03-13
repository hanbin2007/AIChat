//
//  FavoritesView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/12.
//

import SwiftUI

#if os(watchOS)
struct FavoritesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var navigationPath: [UUID]

    var body: some View {
        ZStack {
            AppBackdropView()

            List {
                if chatStore.favoriteConversations.isEmpty {
                    emptyState
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(chatStore.favoriteConversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRowView(
                                conversation: conversation,
                                aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    await chatStore.setConversationFavorite(false, for: conversation.id)
                                }
                            } label: {
                                Label(L10n.tr("favorites.remove"), systemImage: "star.slash")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(L10n.tr("favorites.title"))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("favorites.empty.title"))
                .font(.headline)

            Text(L10n.tr("favorites.empty.message"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
#endif
