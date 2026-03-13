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
    @State private var navigationPath: [UUID] = []
    @State private var selectedPage: RootPage = .conversations
    @State private var isShowingGlobalSettings = false
    @State private var isShowingNewPromptPresetEditor = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $selectedPage) {
                FavoritesView(navigationPath: $navigationPath)
                    .tag(RootPage.favorites)

                ConversationListView(navigationPath: $navigationPath)
                    .tag(RootPage.conversations)

                PromptLibraryView(isShowingNewPresetEditor: $isShowingNewPromptPresetEditor)
                    .tag(RootPage.promptLibrary)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .navigationTitle(rootNavigationTitle)
            .toolbar {
                if navigationPath.isEmpty && selectedPage == .conversations {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isShowingGlobalSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Global settings")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                let newConversationID = await chatStore.createConversation()
                                navigationPath = [newConversationID]
                            }
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New conversation")
                        .disabled(chatStore.isReadOnlyMode)
                    }
                }

                if navigationPath.isEmpty && selectedPage == .promptLibrary {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingNewPromptPresetEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(L10n.tr("prompt_preset.create"))
                    }
                }
            }
            .navigationDestination(for: UUID.self) { conversationID in
                ConversationDetailView(conversationID: conversationID)
            }
        }
        .sheet(isPresented: $isShowingGlobalSettings) {
            GlobalSettingsView()
        }
        .task {
            await chatStore.loadConversationsIfNeeded()
        }
    }

    private var rootNavigationTitle: String {
        switch selectedPage {
        case .favorites:
            return L10n.tr("favorites.title")
        case .conversations:
            return "AIChat"
        case .promptLibrary:
            return L10n.tr("prompt_preset.library.title")
        }
    }
}
#endif
