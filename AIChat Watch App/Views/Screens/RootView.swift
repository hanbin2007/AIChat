//
//  RootView.swift
//  AIChat Watch App
//
//  Top-level NavigationStack. Owns the navigation path and renders the
//  Home screen as the root. All other surfaces are pushed by typed
//  routes — keeps RootView declarative and lets any child trigger a
//  navigation just by appending a `Route` to the bound path.
//
//  Routes carry IDs (or no payload) instead of full models so they
//  stay cheap to hash and survive navigation snapshots.
//

import SwiftUI

enum Route: Hashable {
    case conversationDetail(UUID)
    case allConversations
    case favorites
    case promptLibrary
    case promptEditor(UUID?)             // nil = new preset
    case conversationSettings(UUID)
    case memoryEditor(UUID)
    case archiveBrowser(UUID)
    case globalSettings
    case globalPinnedMemory
    case accountCenter
    case offlineActivation
}

struct RootView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if environment != nil {
                    HomeView(path: $path)
                } else {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "AIChat",
                        subtitle: "Composition root unavailable."
                    )
                }
            }
            .navigationDestination(for: Route.self) { route in
                routeDestination(route)
            }
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .conversationDetail(let id):
            ConversationDetailContainer(id: id)
        case .allConversations:
            ConversationListView(path: $path)
        case .favorites:
            FavoritesView(path: $path)
        case .promptLibrary:
            PromptLibraryView(path: $path)
        case .promptEditor(let id):
            PromptEditorContainer(id: id, path: $path)
        case .conversationSettings(let id):
            ConversationSettingsContainer(id: id, path: $path)
        case .memoryEditor(let id):
            MemoryEditorContainer(id: id)
        case .archiveBrowser(let id):
            ArchiveBrowserContainer(id: id)
        case .globalSettings:
            GlobalSettingsView(path: $path)
        case .globalPinnedMemory:
            GlobalPinnedMemoryView()
        case .accountCenter:
            AccountCenterView(path: $path)
        case .offlineActivation:
            OfflineActivationView()
        }
    }
}
