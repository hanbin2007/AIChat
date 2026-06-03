//
//  ConversationDetailContainer.swift
//  AIChat Watch App
//
//  Resolves a conversation by id, constructs the detail VM, and
//  passes both into the actual view. Splitting the container from the
//  view keeps the heavy SwiftUI body free of environment plumbing.
//

import SwiftUI

struct ConversationDetailContainer: View {
    @Environment(\.appEnvironment) private var environment

    let id: UUID

    @State private var viewModel: ConversationDetailViewModel?
    @State private var settings: SettingsService?
    @State private var billingSnapshot: BillingSnapshot?
    @State private var autoScroll: ConversationAutoScrollController = ConversationAutoScrollController()

    var body: some View {
        Group {
            if let vm = viewModel, let settings {
                ConversationDetailView(
                    viewModel: vm,
                    settings: settings,
                    allowedModelIDs: nil
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard let env = environment,
                  let persistence = env.conversations,
                  let chatService = env.chatService,
                  let transcriptionService = env.transcriptionService else {
                return
            }
            if viewModel == nil {
                if let thread = try? await persistence.conversation(id: id) {
                    viewModel = ConversationDetailViewModel(
                        conversation: thread,
                        chatService: chatService,
                        transcriptionService: transcriptionService,
                        persistence: persistence,
                        connection: env.connectionMonitor,
                        pacer: env.streamingTextPacer,
                        autoScroll: autoScroll,
                        backgroundSession: env.backgroundSession,
                        feedback: env.completionFeedback
                    )
                    settings = env.settingsService
                }
            }
        }
    }
}
