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
    @State private var isShowingGlobalSettings = false
    @State private var isShowingNewPromptPresetEditor = false

    init(initialConversationID: UUID? = nil) {
        self.initialConversationID = initialConversationID
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $selectedPage) {
                FavoritesView(navigationPath: $navigationPath)
                    .tag(RootPage.favorites)

                PromptLibraryView(isShowingNewPresetEditor: $isShowingNewPromptPresetEditor)
                    .tag(RootPage.promptLibrary)

                ConversationListView(navigationPath: $navigationPath)
                    .tag(RootPage.conversations)
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
                                if let newConversationID = await chatStore.createConversation() {
                                    navigationPath = [newConversationID]
                                }
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

                if navigationPath.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        RelayStatusDot()
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

            guard hasAppliedInitialRoute == false,
                  let initialConversationID
            else {
                return
            }

            hasAppliedInitialRoute = true
            selectedPage = .conversations
            navigationPath = [initialConversationID]
        }
        .onOpenURL { url in
            guard let deepLink = AIChatDeepLink(url) else {
                return
            }

            handleDeepLink(deepLink)
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

    private func handleDeepLink(_ deepLink: AIChatDeepLink) {
        switch deepLink {
        case .activationImport:
            return
        case .newConversation:
            selectedPage = .conversations
            guard chatStore.isReadOnlyMode == false else {
                return
            }

            Task {
                if let conversationID = await chatStore.createConversation() {
                    await MainActor.run {
                        navigationPath = [conversationID]
                    }
                }
            }
        }
    }
}
#endif
