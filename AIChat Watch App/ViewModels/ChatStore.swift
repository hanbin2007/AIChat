//
//  ChatStore.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Combine
import Foundation

struct ConversationDraft: Equatable {
    var text: String = ""
    var attachments: [ChatImageAttachment] = []

    var hasContent: Bool {
        text.nonEmptyTrimmed != nil || attachments.isEmpty == false
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [ConversationThread] = []
    @Published private(set) var startupError: String?
    @Published private(set) var sendingConversationIDs: Set<UUID> = []
    @Published private(set) var conversationErrors: [UUID: String] = [:]

    let configuration: AppConfiguration

    private let repository: ConversationRepository
    private let aiService: AIChatService
    private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false

    init(
        repository: ConversationRepository,
        aiService: AIChatService,
        configuration: AppConfiguration
    ) {
        self.repository = repository
        self.aiService = aiService
        self.configuration = configuration
    }

    func loadConversationsIfNeeded() async {
        guard hasLoadedConversations == false else {
            return
        }

        hasLoadedConversations = true

        do {
            conversations = try await repository.loadConversations()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func createConversation() async -> UUID {
        let conversation = ConversationThread.empty()
        conversations.insert(conversation, at: 0)

        do {
            try await repository.save(conversation)
        } catch {
            startupError = error.localizedDescription
        }

        return conversation.id
    }

    func deleteConversation(id: UUID) async {
        conversations.removeAll { $0.id == id }
        drafts[id] = nil
        conversationErrors[id] = nil
        sendingConversationIDs.remove(id)

        do {
            try await repository.deleteConversation(id: id)
        } catch {
            startupError = error.localizedDescription
        }
    }

    func deleteConversations(at offsets: IndexSet) async {
        let ids = offsets.compactMap { index in
            conversations.indices.contains(index) ? conversations[index].id : nil
        }

        for id in ids {
            await deleteConversation(id: id)
        }
    }

    func conversation(id: UUID) -> ConversationThread? {
        conversations.first { $0.id == id }
    }

    func draftText(for conversationID: UUID) -> String {
        drafts[conversationID]?.text ?? ""
    }

    func updateDraftText(_ text: String, for conversationID: UUID) {
        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.text = text
        drafts[conversationID] = draft
    }

    func draftAttachments(for conversationID: UUID) -> [ChatImageAttachment] {
        drafts[conversationID]?.attachments ?? []
    }

    func addAttachment(from rawData: Data, suggestedFilename: String?, to conversationID: UUID) throws {
        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.attachments.append(try ChatImageAttachment.makeNormalized(from: rawData, suggestedFilename: suggestedFilename))
        drafts[conversationID] = draft
    }

    func removeAttachment(id attachmentID: UUID, from conversationID: UUID) {
        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.attachments.removeAll { $0.id == attachmentID }
        drafts[conversationID] = draft
    }

    func isSending(conversationID: UUID) -> Bool {
        sendingConversationIDs.contains(conversationID)
    }

    func errorMessage(for conversationID: UUID) -> String? {
        conversationErrors[conversationID]
    }

    func clearError(for conversationID: UUID) {
        conversationErrors[conversationID] = nil
    }

    func presentError(_ message: String, for conversationID: UUID) {
        conversationErrors[conversationID] = message
    }

    func sendMessage(in conversationID: UUID) async {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            return
        }

        guard configuration.isGeminiConfigured else {
            conversationErrors[conversationID] = configuration.configurationMessage
            return
        }

        let draft = drafts[conversationID] ?? ConversationDraft()
        let trimmedText = draft.text.trimmed

        guard trimmedText.isEmpty == false || draft.attachments.isEmpty == false else {
            return
        }

        conversationErrors[conversationID] = nil

        var currentConversation = conversations[index]
        let userMessage = ChatMessage(
            role: .user,
            text: trimmedText,
            attachments: draft.attachments
        )
        currentConversation.append(userMessage)
        drafts[conversationID] = ConversationDraft()
        upsertConversation(currentConversation)

        do {
            try await repository.save(currentConversation)
        } catch {
            startupError = error.localizedDescription
        }

        sendingConversationIDs.insert(conversationID)

        do {
            let assistantReply = try await aiService.generateReply(for: currentConversation)
            guard var refreshedConversation = self.conversation(id: conversationID) else {
                sendingConversationIDs.remove(conversationID)
                return
            }

            refreshedConversation.append(
                ChatMessage(
                    role: .assistant,
                    text: assistantReply
                )
            )
            upsertConversation(refreshedConversation)
            sendingConversationIDs.remove(conversationID)
            try await repository.save(refreshedConversation)
        } catch {
            sendingConversationIDs.remove(conversationID)
            conversationErrors[conversationID] = error.localizedDescription
        }
    }

    private func upsertConversation(_ conversation: ConversationThread) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }
}
