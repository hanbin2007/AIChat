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
    var attachments: [ChatAttachment] = []

    var hasContent: Bool {
        text.nonEmptyTrimmed != nil || attachments.isEmpty == false
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [ConversationThread] = []
    @Published private(set) var startupError: String?
    @Published private(set) var sendingConversationIDs: Set<UUID> = []
    @Published private(set) var transcribingConversationIDs: Set<UUID> = []
    @Published private(set) var conversationErrors: [UUID: String] = [:]
    @Published private(set) var syncStatusDescription: String
    @Published private(set) var activationState: OfflineActivationState?

    let configuration: AppConfiguration
    let storageDescription: String
    let deviceIdentity: WatchDeviceIdentity

    private let repository: ConversationRepository
    private let aiService: AIStreamingService
    private let transcriptionService: AITranscriptionService?
    private let syncBridge: CompanionSyncBridge
    private let activationRepository: ActivationRepository
    @Published private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false

    init(
        repository: ConversationRepository,
        aiService: AIStreamingService,
        transcriptionService: AITranscriptionService?,
        configuration: AppConfiguration,
        syncBridge: CompanionSyncBridge,
        activationRepository: ActivationRepository = ActivationRepository(),
        deviceIdentity: WatchDeviceIdentity? = nil
    ) {
        self.repository = repository
        self.aiService = aiService
        self.transcriptionService = transcriptionService
        self.configuration = configuration
        self.syncBridge = syncBridge
        self.activationRepository = activationRepository
        self.deviceIdentity = deviceIdentity ?? WatchDeviceIdentityProvider.current()
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

    var activationStatus: OfflineActivationStatus {
        OfflineActivation.status(for: activationState, deviceToken: deviceIdentity.deviceToken)
    }

    var isReadOnlyMode: Bool {
        switch activationStatus {
        case .active:
            return false
        case .inactive, .pending, .expired, .exhausted, .invalid:
            return true
        }
    }

    var activationStatusTitle: String {
        switch activationStatus {
        case .inactive:
            return "未激活"
        case .pending:
            return "授权未生效"
        case .active:
            return "已激活"
        case .expired:
            return "授权已过期"
        case .exhausted:
            return "次数已用尽"
        case .invalid:
            return "授权无效"
        }
    }

    var activationStatusMessage: String {
        switch activationStatus {
        case .inactive:
            return "当前只能查看历史消息。发新消息前，需要在 Apple Watch 上完成离线激活。"
        case .pending(let state):
            return OfflineActivationError.notYetActive(startDate: state.license.validFrom).localizedDescription
        case .active(let state, let remainingMessages):
            var components: [String] = []
            if let validUntil = state.license.validUntil {
                components.append("有效期至 \(validUntil.formatted(date: .abbreviated, time: .shortened))")
            } else {
                components.append("长期有效")
            }

            if let remainingMessages {
                components.append("剩余 \(remainingMessages) 次")
            } else {
                components.append("次数不限")
            }

            components.append("模型: \(allowedModelsDescription(for: state.license.allowedModelIDs))")
            return components.joined(separator: " • ")
        case .expired(let state):
            if let validUntil = state.license.validUntil {
                return "授权已于 \(validUntil.formatted(date: .abbreviated, time: .shortened)) 过期，请重新激活。"
            }
            return "当前授权不可用，请重新激活。"
        case .exhausted(let state):
            return "当前授权的 \(state.license.messageLimit ?? 0) 次发送额度已用完，请重新生成激活码。"
        case .invalid(let message):
            return message
        }
    }

    var activationAllowedModelIDs: Set<String>? {
        OfflineActivation.allowedModelIDs(
            for: activationState,
            deviceToken: deviceIdentity.deviceToken
        )
    }

    func loadConversationsIfNeeded() async {
        guard hasLoadedConversations == false else {
            return
        }

        hasLoadedConversations = true
        await refreshActivationState()

        do {
            conversations = try await repository.loadConversations()
            syncBridge.requestBootstrapIfPossible()
        } catch {
            startupError = error.localizedDescription
        }
    }

    func refreshActivationState() async {
        activationState = await activationRepository.loadState()
    }

    func activationRequestCode(now: Date = .now) -> String {
        OfflineActivation.makeRequestCode(deviceToken: deviceIdentity.deviceToken, now: now)
    }

    func applyActivationCode(_ rawCode: String, now: Date = .now) async throws {
        let nextState = try OfflineActivation.activate(
            code: rawCode,
            deviceToken: deviceIdentity.deviceToken,
            now: now,
            currentState: activationState
        )
        try await activationRepository.saveState(nextState)
        activationState = nextState
    }

    func clearActivation() async {
        await activationRepository.clearState()
        activationState = nil
    }

    func createConversation() async -> UUID {
        let conversation = ConversationThread.empty()
        conversations.insert(conversation, at: 0)
        await persist(conversation, sync: true)
        return conversation.id
    }

    func renameConversation(id: UUID, title: String) async {
        guard isReadOnlyMode == false, var conversation = conversation(id: id) else {
            return
        }

        conversation.updateTitle(title)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    func aiConfiguration(for conversationID: UUID) -> ConversationAIConfiguration {
        if let conversation = conversation(id: conversationID) {
            return licensedConfiguration(
                from: conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
            )
        }

        return licensedConfiguration(from: ConversationAIConfiguration(model: configuration.geminiModel))
    }

    func availableModelOptions() -> [AIModelOption] {
        AIModelCatalog.quickOptions(
            defaultModel: configuration.geminiModel,
            allowedModelIDs: activationAllowedModelIDs
        )
    }

    func updateModel(_ model: String, for conversationID: UUID) async {
        if let activationMessage = activationFailureMessage(for: model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.model = model
        }
    }

    func updateThinkingIntensity(_ thinkingIntensity: AIThinkingIntensity, for conversationID: UUID) async {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.thinkingIntensity = thinkingIntensity
        }
    }

    func clearConversation(id: UUID) async {
        guard isReadOnlyMode == false, var conversation = conversation(id: id) else {
            return
        }

        conversation.clearMessages()
        drafts[id] = ConversationDraft()
        conversationErrors[id] = nil
        transcribingConversationIDs.remove(id)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    func deleteConversation(id: UUID) async {
        guard isReadOnlyMode == false else {
            return
        }

        await deleteConversation(id: id, sync: true)
    }

    func deleteConversations(at offsets: IndexSet) async {
        guard isReadOnlyMode == false else {
            return
        }

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
        guard isReadOnlyMode == false else {
            return
        }

        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.text = text
        drafts[conversationID] = draft
    }

    func draftAttachments(for conversationID: UUID) -> [ChatAttachment] {
        drafts[conversationID]?.attachments ?? []
    }

    func addAttachment(from rawData: Data, suggestedFilename: String?, to conversationID: UUID) throws {
        guard isReadOnlyMode == false else {
            throw OfflineActivationError.notActivated
        }

        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.attachments.append(
            try ChatAttachment.makeNormalizedImage(from: rawData, suggestedFilename: suggestedFilename)
        )
        drafts[conversationID] = draft
    }

    func addRecordedAudio(
        from rawData: Data,
        suggestedFilename: String?,
        durationSeconds: Double,
        to conversationID: UUID
    ) throws {
        guard isReadOnlyMode == false else {
            throw OfflineActivationError.notActivated
        }

        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.attachments.append(
            try ChatAttachment.makeRecordedAudio(
                from: rawData,
                suggestedFilename: suggestedFilename,
                durationSeconds: durationSeconds
            )
        )
        drafts[conversationID] = draft
    }

    func removeAttachment(id attachmentID: UUID, from conversationID: UUID) {
        guard isReadOnlyMode == false else {
            return
        }

        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.attachments.removeAll { $0.id == attachmentID }
        drafts[conversationID] = draft
    }

    func isSending(conversationID: UUID) -> Bool {
        sendingConversationIDs.contains(conversationID)
    }

    func isTranscribing(conversationID: UUID) -> Bool {
        transcribingConversationIDs.contains(conversationID)
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
        let draft = drafts[conversationID] ?? ConversationDraft()
        await send(draft: draft, in: conversationID, clearStoredDraft: true)
    }

    func sendRecordedAudio(_ audioAttachment: ChatAttachment, in conversationID: UUID) async {
        guard configuration.isAIConfigured else {
            conversationErrors[conversationID] = configuration.configurationMessage
            return
        }

        guard let transcriptionService else {
            conversationErrors[conversationID] =
                configuration.voiceInputConfigurationMessage ??
                VoiceTranscriptionError.unavailable.localizedDescription
            return
        }

        guard audioAttachment.isAudio else {
            conversationErrors[conversationID] = VoiceTranscriptionError.invalidAudio.localizedDescription
            return
        }

        guard isSending(conversationID: conversationID) == false,
              isTranscribing(conversationID: conversationID) == false,
              let currentConversation = conversation(id: conversationID)
        else {
            return
        }

        let effectiveAIConfiguration = licensedConfiguration(
            from: currentConversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        )
        if let activationMessage = activationFailureMessage(for: effectiveAIConfiguration.model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        conversationErrors[conversationID] = nil
        transcribingConversationIDs.insert(conversationID)

        do {
            let transcription = try await transcriptionService.transcribeUserAudio(
                audioAttachment,
                in: currentConversation
            )

            transcribingConversationIDs.remove(conversationID)
            await send(
                draft: ConversationDraft(text: transcription.text, attachments: []),
                in: conversationID,
                clearStoredDraft: false
            )
        } catch {
            transcribingConversationIDs.remove(conversationID)
            conversationErrors[conversationID] = error.localizedDescription
        }
    }

    private func send(
        draft: ConversationDraft,
        in conversationID: UUID,
        clearStoredDraft: Bool
    ) async {
        guard configuration.isAIConfigured else {
            conversationErrors[conversationID] = configuration.configurationMessage
            return
        }

        guard var currentConversation = conversation(id: conversationID) else {
            return
        }

        let effectiveAIConfiguration = licensedConfiguration(
            from: currentConversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        )
        if let activationMessage = activationFailureMessage(for: effectiveAIConfiguration.model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        let currentConfiguration = currentConversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        if currentConfiguration != effectiveAIConfiguration {
            currentConversation.updateAIConfiguration(effectiveAIConfiguration)
            upsertConversation(currentConversation)
            await persist(currentConversation, sync: true)
        }
        let trimmedText = draft.text.trimmed

        guard trimmedText.isEmpty == false || draft.attachments.isEmpty == false else {
            return
        }

        do {
            let nextActivationState = try OfflineActivation.consumeMessage(
                from: activationState,
                deviceToken: deviceIdentity.deviceToken,
                modelID: effectiveAIConfiguration.model
            )
            if nextActivationState != activationState {
                try await activationRepository.saveState(nextActivationState)
                activationState = nextActivationState
            }
        } catch {
            conversationErrors[conversationID] = error.localizedDescription
            return
        }

        conversationErrors[conversationID] = nil

        let userMessage = ChatMessage(
            role: .user,
            text: trimmedText,
            attachments: draft.attachments
        )
        currentConversation.append(userMessage)
        if clearStoredDraft {
            drafts[conversationID] = ConversationDraft()
        }
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
        transcribingConversationIDs.remove(id)

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
        resolvedConfiguration = licensedConfiguration(from: resolvedConfiguration)
        conversation.updateAIConfiguration(resolvedConfiguration)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    private func licensedConfiguration(from configuration: ConversationAIConfiguration) -> ConversationAIConfiguration {
        var resolvedConfiguration = configuration
        resolvedConfiguration.model = OfflineActivation.recommendedModel(
            preferredModelID: configuration.model,
            defaultModelID: self.configuration.geminiModel,
            state: activationState,
            deviceToken: deviceIdentity.deviceToken
        )
        return resolvedConfiguration
    }

    private func activationFailureMessage(for modelID: String) -> String? {
        switch activationStatus {
        case .inactive:
            return OfflineActivationError.notActivated.localizedDescription
        case .pending(let state):
            return OfflineActivationError.notYetActive(startDate: state.license.validFrom).localizedDescription
        case .expired:
            return OfflineActivationError.licenseExpired.localizedDescription
        case .exhausted:
            return OfflineActivationError.messageLimitReached.localizedDescription
        case .invalid(let message):
            return message
        case .active(let state, _):
            return state.license.allows(modelID: modelID) ? nil : OfflineActivationError.modelNotAllowed.localizedDescription
        }
    }

    private func allowedModelsDescription(for allowedModelIDs: Set<String>?) -> String {
        guard let allowedModelIDs else {
            return "全部"
        }

        let titles = LicensedModelCatalog.supportedModels
            .filter { allowedModelIDs.contains($0.id) }
            .map(\.title)

        return titles.isEmpty ? "全部" : titles.joined(separator: "、")
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

private struct PreviewAITranscriptionService: AITranscriptionService {
    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread
    ) async throws -> VoiceTranscriptionResult {
        VoiceTranscriptionResult(
            text: "This is a preview voice transcript.",
            model: "gemini-3-flash-preview"
        )
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
            geminiTranscriptionModel: "gemini-3-flash-preview",
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
            transcriptionService: PreviewAITranscriptionService(),
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
        store.transcribingConversationIDs = []
        store.conversationErrors = conversationErrors
        store.startupError = startupError
        store.activationState = OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: store.deviceIdentity.deviceToken,
                requestIssuedAt: .now,
                validFrom: .now,
                validUntil: nil,
                messageLimit: nil,
                modelMask: LicensedModelCatalog.unrestrictedMask
            ),
            activationCodeFingerprint: "preview",
            activatedAt: .now,
            usedMessageCount: 0
        )
        store.hasLoadedConversations = true
        return store
    }
}
#endif
