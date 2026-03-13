#if COMPANION_APP
//
//  CompanionFavoritesView.swift
//  AIChat
//
//  Created by Codex on 2026/3/12.
//

import SwiftUI

struct CompanionFavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    @Binding var selectedConversationID: UUID?

    var body: some View {
        NavigationStack {
            List {
                if chatStore.favoriteConversations.isEmpty {
                    Text(L10n.tr("favorites.empty.message"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(chatStore.favoriteConversations) { conversation in
                        Button {
                            selectedConversationID = conversation.id
                            dismiss()
                        } label: {
                            CompanionConversationRow(
                                conversation: conversation,
                                aiConfiguration: chatStore.aiConfiguration(for: conversation.id)
                            )
                        }
                        .buttonStyle(.plain)
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppBackdropView())
            .navigationTitle(L10n.tr("favorites.title"))
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
#endif
