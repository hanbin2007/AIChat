//
//  ContentView.swift
//  AIChat Watch App
//
//  Created by zhb on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
private enum RootPage: Hashable {
    case favorites
    case conversations
    case promptLibrary
}

struct ContentView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let initialConversationID: UUID?
    @State private var navigationPath: [UUID] = []
    @State private var selectedPage: RootPage = .conversations
    @State private var hasAppliedInitialRoute = false

    init(initialConversationID: UUID? = nil) {
        self.initialConversationID = initialConversationID
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $selectedPage) {
                FavoritesView(navigationPath: $navigationPath)
                    .tag(RootPage.favorites)

                ConversationListView(navigationPath: $navigationPath)
                    .tag(RootPage.conversations)

                PromptLibraryView()
                    .tag(RootPage.promptLibrary)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
                .navigationDestination(for: UUID.self) { conversationID in
                    ConversationDetailView(conversationID: conversationID)
                }
        }
        .task {
            await chatStore.loadConversationsIfNeeded()

            guard hasAppliedInitialRoute == false,
                  let initialConversationID
            else {
                return
            }

            hasAppliedInitialRoute = true
            selectedPage = .conversations
            navigationPath = [initialConversationID]
        }
    }
}
#endif
