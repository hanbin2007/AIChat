//
//  ConversationSettingsContainer.swift
//  AIChat Watch App
//
//  Loads the conversation by id, builds the settings VM, and renders
//  the actual settings screen. Mirrors the detail container pattern.
//

import SwiftUI

struct ConversationSettingsContainer: View {
    @Environment(\.appEnvironment) private var environment

    let id: UUID
    @Binding var path: NavigationPath

    @State private var viewModel: ConversationSettingsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                ConversationSettingsView(viewModel: vm, path: $path)
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
