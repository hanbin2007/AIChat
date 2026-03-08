//
//  ConversationSettingsView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import SwiftUI

struct ConversationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    let conversationID: UUID

    @State private var draftTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Conversation") {
                    TextField("Title", text: $draftTitle)
                    Button("Save Title") {
                        Task {
                            await chatStore.renameConversation(id: conversationID, title: draftTitle)
                            dismiss()
                        }
                    }
                    .disabled(draftTitle.trimmed.isEmpty)

                    Button("Clear Messages", role: .destructive) {
                        Task {
                            await chatStore.clearConversation(id: conversationID)
                            dismiss()
                        }
                    }
                }

                Section("Runtime") {
                    LabeledContent("Backend", value: chatStore.configuration.backendSummary)
                    LabeledContent("Storage", value: chatStore.storageDescription)
                    LabeledContent("Sync", value: chatStore.syncStatusDescription)
                }

                Section("Danger Zone") {
                    Button("Delete Conversation", role: .destructive) {
                        Task {
                            await chatStore.deleteConversation(id: conversationID)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Manage Chat")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                draftTitle = chatStore.conversation(id: conversationID)?.title ?? ""
            }
        }
    }
}
