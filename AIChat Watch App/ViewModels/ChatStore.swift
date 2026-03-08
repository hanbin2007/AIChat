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
    @Published private(set) var syncStatusDescription: String

    let configuration: AppConfiguration
    let storageDescription: String

    private let repository: ConversationRepository
    private let aiService: AIStreamingService
    private let syncBridge: CompanionSyncBridge
    private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false

    init(
        repository: ConversationRepository,
        aiService: AIStreamingService,
        configuration: AppConfiguration,
        syncBridge: CompanionSyncBridge
    ) {
        self.repository = repository
        self.aiService = aiService
        self.configuration = configuration
        self.syncBridge = syncBridge
        self.storageDescription = repository.storageDescription
        self.syncStatusDescription = syncBridge.currentStatus.description

        syncBridge.setStatusHandler { [weak self] status in
            self?.syncStatusDescription = status.description
        }

        syncBridge.setEventHandler { [weak self] event in
            Task { @MainActor in
                await self?.handleSyncEvent(event)
            }
        }
    }

    func loadConversationsIfNeeded() async {
        guard hasLoadedConversations == false else {
            return
        }

        hasLoadedConversations = true

        do {
            conversations = try await repository.loadConversations()
            syncBridge.requestBootstrapIfPossible()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func createConversation() async -> UUID {
        let conversation = ConversationThread.empty()
        conversations.insert(conversation, at: 0)
        await persist(conversation, sync: true)
        return conversation.id
    }

    func renameConversation(id: UUID, title: String) async {
        guard var conversation = conversation(id: id) else {
            return
        }

        conversation.updateTitle(title)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    func aiConfiguration(for conversationID: UUID) -> ConversationAIConfiguration {
        if let conversation = conversation(id: conversationID) {
            return conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        }

        return ConversationAIConfiguration(model: configuration.geminiModel)
    }

    func updateModel(_ model: String, for conversationID: UUID) async {
        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.model = model
        }
    }

    func updateThinkingIntensity(_ thinkingIntensity: AIThinkingIntensity, for conversationID: UUID) async {
        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.thinkingIntensity = thinkingIntensity
        }
    }

    func clearConversation(id: UUID) async {
        guard var conversation = conversation(id: id) else {
            return
        }

        conversation.clearMessages()
        drafts[id] = ConversationDraft()
        conversationErrors[id] = nil
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    func deleteConversation(id: UUID) async {
        await deleteConversation(id: id, sync: true)
    }

    func deleteConversations(at offsets: IndexSet) async {
        let ids = offsets.compactMap { index in
            conversations.indices.contains(index) ? conversations[index].id : nil
        }

        for id in ids {
            await deleteConversation(id: id, sync: true)
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
        guard configuration.isAIConfigured else {
            conversationErrors[conversationID] = configuration.configurationMessage
            return
        }

        guard var currentConversation = conversation(id: conversationID) else {
            return
        }

        let draft = drafts[conversationID] ?? ConversationDraft()
        let trimmedText = draft.text.trimmed

        guard trimmedText.isEmpty == false || draft.attachments.isEmpty == false else {
            return
        }

        conversationErrors[conversationID] = nil

        let userMessage = ChatMessage(
            role: .user,
            text: trimmedText,
            attachments: draft.attachments
        )
        currentConversation.append(userMessage)
        drafts[conversationID] = ConversationDraft()
        upsertConversation(currentConversation)
        await persist(currentConversation, sync: true)

        let requestConversation = currentConversation
        let assistantMessageID = UUID()
        currentConversation.append(
            ChatMessage(
                id: assistantMessageID,
                role: .assistant,
                text: "",
                status: .streaming
            )
        )
        upsertConversation(currentConversation)
        sendingConversationIDs.insert(conversationID)

        var streamedText = ""
        var streamedThoughtSummary = ""

        do {
            for try await event in aiService.streamReply(for: requestConversation) {
                switch event {
                case .answerDelta(let delta):
                    streamedText.append(delta)
                case .thoughtDelta(let delta):
                    streamedThoughtSummary.append(delta)
                }

                mutateConversation(id: conversationID) { conversation in
                    conversation.upsertMessage(
                        ChatMessage(
                            id: assistantMessageID,
                            role: .assistant,
                            text: streamedText,
                            thoughtSummary: streamedThoughtSummary.nonEmptyTrimmed,
                            createdAt: conversation.messages.first(where: { $0.id == assistantMessageID })?.createdAt ?? .now,
                            status: .streaming
                        )
                    )
                }
            }

            mutateConversation(id: conversationID) { conversation in
                conversation.upsertMessage(
                    ChatMessage(
                        id: assistantMessageID,
                        role: .assistant,
                        text: streamedText,
                        thoughtSummary: streamedThoughtSummary.nonEmptyTrimmed,
                        createdAt: conversation.messages.first(where: { $0.id == assistantMessageID })?.createdAt ?? .now,
                        status: .sent
                    )
                )
            }

            sendingConversationIDs.remove(conversationID)

            if let finalizedConversation = conversation(id: conversationID) {
                await persist(finalizedConversation, sync: true)
            }
        } catch {
            sendingConversationIDs.remove(conversationID)
            conversationErrors[conversationID] = error.localizedDescription

            mutateConversation(id: conversationID) { conversation in
                if streamedText.isEmpty, streamedThoughtSummary.isEmpty {
                    conversation.removeMessage(id: assistantMessageID)
                } else {
                    conversation.upsertMessage(
                        ChatMessage(
                            id: assistantMessageID,
                            role: .assistant,
                            text: streamedText,
                            thoughtSummary: streamedThoughtSummary.nonEmptyTrimmed,
                            createdAt: conversation.messages.first(where: { $0.id == assistantMessageID })?.createdAt ?? .now,
                            status: .failed
                        )
                    )
                }
            }

            if let failedConversation = conversation(id: conversationID) {
                await persist(failedConversation, sync: true)
            }
        }
    }

    private func persist(_ conversation: ConversationThread, sync: Bool) async {
        do {
            try await repository.save(conversation)
            if sync {
                syncBridge.pushConversation(conversation)
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func deleteConversation(id: UUID, sync: Bool) async {
        conversations.removeAll { $0.id == id }
        drafts[id] = nil
        conversationErrors[id] = nil
        sendingConversationIDs.remove(id)

        do {
            try await repository.deleteConversation(id: id)
            if sync {
                syncBridge.pushDeletion(conversationID: id)
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func upsertConversation(_ conversation: ConversationThread) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.insert(conversation, at: 0)
    }

    private func mutateConversation(id: UUID, mutation: (inout ConversationThread) -> Void) {
        guard var conversation = conversation(id: id) else {
            return
        }

        mutation(&conversation)
        upsertConversation(conversation)
    }

    private func updateAIConfiguration(
        for conversationID: UUID,
        mutation: (inout ConversationAIConfiguration) -> Void
    ) async {
        guard var conversation = conversation(id: conversationID) else {
            return
        }

        var resolvedConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        mutation(&resolvedConfiguration)
        conversation.updateAIConfiguration(resolvedConfiguration)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    private func handleSyncEvent(_ event: CompanionSyncEvent) async {
        switch event {
        case .upsert(let conversation):
            upsertConversation(conversation)
            await persist(conversation, sync: false)
        case .delete(let conversationID):
            await deleteConversation(id: conversationID, sync: false)
        }
    }
}

#if DEBUG
private struct PreviewAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.thoughtDelta("Reviewing the draft and condensing the most useful points."))
            continuation.yield(.answerDelta("This is a preview reply from the mock AI service."))
            continuation.finish()
        }
    }
}

extension ChatStore {
    static func previewStore(
        conversations: [ConversationThread],
        drafts: [UUID: ConversationDraft] = [:],
        sendingConversationIDs: Set<UUID> = [],
        conversationErrors: [UUID: String] = [:],
        startupError: String? = nil,
        configuration: AppConfiguration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "preview-key",
            geminiModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
    ) -> ChatStore {
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatPreview-\(UUID().uuidString)", isDirectory: true)
        )

        let store = ChatStore(
            repository: repository,
            aiService: PreviewAIStreamingService(),
            configuration: configuration,
            syncBridge: CompanionSyncBridge()
        )

        store.conversations = conversations.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.updatedAt > rhs.updatedAt
        }
        store.drafts = drafts
        store.sendingConversationIDs = sendingConversationIDs
        store.conversationErrors = conversationErrors
        store.startupError = startupError
        store.hasLoadedConversations = true
        return store
    }
}
#endif
