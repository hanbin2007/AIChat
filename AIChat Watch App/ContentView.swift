//
//  ContentView.swift
//  AIChat Watch App
//
//  Created by zhb on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
struct ContentView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var navigationPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ConversationListView(navigationPath: $navigationPath)
                .navigationDestination(for: UUID.self) { conversationID in
                    ConversationDetailView(conversationID: conversationID)
                }
        }
        .task {
            await chatStore.loadConversationsIfNeeded()
        }
    }
}
#endif
