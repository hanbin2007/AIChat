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
    static let defaultSendFailureRetryLimit = 3
    static let maximumSendFailureRetryLimit = 10
    static let minimumSendFailureRetryLimit = 1

    @Published private(set) var conversations: [ConversationThread] = []
    @Published private(set) var startupError: String?
    @Published private(set) var sendingConversationIDs: Set<UUID> = []
    @Published private(set) var transcribingConversationIDs: Set<UUID> = []
    @Published private(set) var conversationErrors: [UUID: String] = [:]
    @Published private(set) var syncStatusDescription: String
    @Published private(set) var activationState: OfflineActivationState?
    @Published private(set) var sendFailureRetryLimit: Int
    @Published private(set) var defaultConversationConfiguration: ConversationAIConfiguration
    @Published private(set) var transcriptionModel: String
    @Published private(set) var transcriptionCustomPrompt: String
    @Published private(set) var transcriptionIncludesContext: Bool

    let configuration: AppConfiguration
    let storageDescription: String
    let deviceIdentity: WatchDeviceIdentity

    private let repository: ConversationRepository
    private let aiService: AIStreamingService
    private let transcriptionService: AITranscriptionService?
    private let syncBridge: CompanionSyncBridge
    private let activationRepository: ActivationRepository
    private let defaults: UserDefaults
    private let sendRetryDelayNanoseconds: @Sendable (Int) -> UInt64
    @Published private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false
    private var sendTasks: [UUID: Task<Void, Never>] = [:]

    init(
        repository: ConversationRepository,
        aiService: AIStreamingService,
        transcriptionService: AITranscriptionService?,
        configuration: AppConfiguration,
        syncBridge: CompanionSyncBridge,
        activationRepository: ActivationRepository = ActivationRepository(),
        deviceIdentity: WatchDeviceIdentity? = nil,
        defaults: UserDefaults? = nil,
        sendRetryDelayNanoseconds: @escaping @Sendable (Int) -> UInt64 = ChatStore.defaultSendRetryDelayNanoseconds
    ) {
        let resolvedDefaults = defaults ?? Self.makeDefaults(configuration: configuration)
        self.repository = repository
        self.aiService = aiService
        self.transcriptionService = transcriptionService
        self.configuration = configuration
        self.syncBridge = syncBridge
        self.activationRepository = activationRepository
        self.deviceIdentity = deviceIdentity ?? WatchDeviceIdentityProvider.current()
        self.defaults = resolvedDefaults
        self.sendRetryDelayNanoseconds = sendRetryDelayNanoseconds
        self.storageDescription = repository.storageDescription
        self.syncStatusDescription = syncBridge.currentStatus.description
        self.sendFailureRetryLimit = Self.loadSendFailureRetryLimit(from: resolvedDefaults)
        self.defaultConversationConfiguration = Self.loadDefaultConversationConfiguration(
            from: resolvedDefaults,
            fallbackModel: configuration.geminiModel
        )
        self.transcriptionModel = Self.loadTranscriptionModel(
            from: resolvedDefaults,
            fallbackModel: configuration.geminiTranscriptionModel
        )
        self.transcriptionCustomPrompt = Self.loadTranscriptionCustomPrompt(from: resolvedDefaults)
        self.transcriptionIncludesContext = Self.loadTranscriptionIncludesContext(from: resolvedDefaults)

        syncBridge.setStatusHandler { [weak self] status in
            self?.syncStatusDescription = status.description
        }

        syncBridge.setSnapshotProvider { [weak self] in
            self?.conversations ?? []
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
            return "当前只能查看历史消息。发新消息前，需要先完成当前设备的离线激活。"
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
        let conversation = ConversationThread.empty(
            aiConfiguration: defaultConversationConfiguration
        )
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

        return licensedConfiguration(from: defaultConversationConfiguration)
    }

    func availableModelOptions() -> [AIModelOption] {
        AIModelCatalog.quickOptions(
            defaultModel: configuration.geminiModel,
            allowedModelIDs: activationAllowedModelIDs
        )
    }

    var selectedTranscriptionModel: String {
        transcriptionModel
    }

    func availableTranscriptionModelOptions() -> [AITranscriptionModelOption] {
        AITranscriptionModelCatalog.options(defaultModel: configuration.geminiTranscriptionModel)
    }

    func availableThinkingIntensities(for conversationID: UUID) -> [AIThinkingIntensity] {
        let configuration = aiConfiguration(for: conversationID)
        return AIModelCatalog.availableThinkingIntensities(for: configuration.model)
    }

    func availableDefaultThinkingIntensities() -> [AIThinkingIntensity] {
        AIModelCatalog.availableThinkingIntensities(for: defaultConversationConfiguration.model)
    }

    var defaultConversationSystemPrompt: String {
        defaultConversationConfiguration.customSystemPrompt ?? ""
    }

    var selectedTranscriptionCustomPrompt: String {
        transcriptionCustomPrompt
    }

    var isTranscriptionContextEnabled: Bool {
        transcriptionIncludesContext
    }

    func updateModel(_ model: String, for conversationID: UUID) async {
        if let activationMessage = activationFailureMessage(for: model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.model = model
            configuration.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
                configuration.thinkingIntensity,
                for: model
            )
        }
    }

    func updateThinkingIntensity(_ thinkingIntensity: AIThinkingIntensity, for conversationID: UUID) async {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
                thinkingIntensity,
                for: configuration.model
            )
        }
    }

    func updateSystemPromptMode(_ systemPromptMode: AISystemPromptMode, for conversationID: UUID) async {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.systemPromptMode = systemPromptMode
        }
    }

    func updateCustomSystemPrompt(
        _ prompt: String,
        for conversationID: UUID
    ) async {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.customSystemPrompt = prompt.nonEmptyTrimmed
        }
    }

    func clearConversation(id: UUID) async {
        guard isReadOnlyMode == false, var conversation = conversation(id: id) else {
            return
        }

        sendTasks[id]?.cancel()
        sendTasks[id] = nil
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

    func canRetryLatestReply(in conversationID: UUID) -> Bool {
        guard isReadOnlyMode == false,
              configuration.isAIConfigured,
              isSending(conversationID: conversationID) == false,
              isTranscribing(conversationID: conversationID) == false,
              let conversation = conversation(id: conversationID)
        else {
            return false
        }

        return conversation.messages.lastIndex(where: { $0.role == .user }) != nil
    }

    func updateSendFailureRetryLimit(_ limit: Int) {
        let normalizedLimit = Self.normalizedSendFailureRetryLimit(limit)
        guard normalizedLimit != sendFailureRetryLimit else {
            return
        }

        sendFailureRetryLimit = normalizedLimit
        defaults.set(normalizedLimit, forKey: DefaultsKeys.sendFailureRetryLimit)
    }

    func updateDefaultConversationModel(_ model: String) {
        let normalizedThinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            defaultConversationConfiguration.thinkingIntensity,
            for: model
        )

        guard defaultConversationConfiguration.model != model ||
                defaultConversationConfiguration.thinkingIntensity != normalizedThinkingIntensity
        else {
            return
        }

        defaultConversationConfiguration.model = model
        defaultConversationConfiguration.thinkingIntensity = normalizedThinkingIntensity
        persistDefaultConversationConfiguration()
    }

    func updateDefaultConversationThinkingIntensity(_ thinkingIntensity: AIThinkingIntensity) {
        let normalizedThinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            thinkingIntensity,
            for: defaultConversationConfiguration.model
        )

        guard defaultConversationConfiguration.thinkingIntensity != normalizedThinkingIntensity else {
            return
        }

        defaultConversationConfiguration.thinkingIntensity = normalizedThinkingIntensity
        persistDefaultConversationConfiguration()
    }

    func updateDefaultConversationSystemPrompt(_ prompt: String) {
        let normalizedPrompt = prompt.nonEmptyTrimmed
        guard defaultConversationConfiguration.customSystemPrompt != normalizedPrompt else {
            return
        }

        defaultConversationConfiguration.customSystemPrompt = normalizedPrompt
        persistDefaultConversationConfiguration()
    }

    func updateTranscriptionModel(_ model: String) {
        let normalizedModel = AITranscriptionModelCatalog.normalizedModel(
            model,
            defaultModel: configuration.geminiTranscriptionModel
        )
        guard normalizedModel != transcriptionModel else {
            return
        }

        transcriptionModel = normalizedModel
        defaults.set(normalizedModel, forKey: DefaultsKeys.transcriptionModel)
    }

    func updateTranscriptionCustomPrompt(_ prompt: String) {
        let normalizedPrompt = prompt
        guard transcriptionCustomPrompt != normalizedPrompt else {
            return
        }

        transcriptionCustomPrompt = normalizedPrompt
        defaults.set(normalizedPrompt, forKey: DefaultsKeys.transcriptionCustomPrompt)
    }

    func updateTranscriptionIncludesContext(_ includesContext: Bool) {
        guard transcriptionIncludesContext != includesContext else {
            return
        }

        transcriptionIncludesContext = includesContext
        defaults.set(includesContext, forKey: DefaultsKeys.transcriptionIncludesContext)
    }

    func sendMessage(in conversationID: UUID) async {
        let draft = drafts[conversationID] ?? ConversationDraft()
        await runSendTask(for: conversationID) { store in
            await store.send(draft: draft, in: conversationID, clearStoredDraft: true)
        }
    }

    func retryLatestReply(in conversationID: UUID) async {
        await runSendTask(for: conversationID) { store in
            await store.retryLatestAssistantReply(in: conversationID)
        }
    }

    func stopSending(in conversationID: UUID) {
        conversationErrors[conversationID] = nil
        sendTasks[conversationID]?.cancel()
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

        let transcriptionConfiguration = VoiceTranscriptionConfiguration(
            model: selectedTranscriptionModel,
            customPrompt: selectedTranscriptionCustomPrompt,
            includesContext: isTranscriptionContextEnabled
        )
        let maximumRetryCount = sendFailureRetryLimit
        var finalError: Error?
        var attemptCount = 0

        for attempt in 0...maximumRetryCount {
            attemptCount = attempt + 1

            if attempt > 0 {
                let delay = sendRetryDelayNanoseconds(attempt)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            do {
                let transcription = try await transcriptionService.transcribeUserAudio(
                    audioAttachment,
                    in: currentConversation,
                    using: transcriptionConfiguration
                )

                transcribingConversationIDs.remove(conversationID)
                var draft = drafts[conversationID] ?? ConversationDraft()
                draft.text = transcription.text
                drafts[conversationID] = draft
                return
            } catch {
                finalError = error

                let hasRemainingRetries = attempt < maximumRetryCount
                guard hasRemainingRetries, shouldRetryTranscription(after: error) else {
                    break
                }
            }
        }

        transcribingConversationIDs.remove(conversationID)
        if let finalError {
            conversationErrors[conversationID] = failureMessage(
                from: finalError,
                automaticRetryCount: max(0, attemptCount - 1),
                operation: "语音转录"
            )
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
            try await consumeActivationMessage(for: effectiveAIConfiguration.model)
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
        await streamAssistantReply(for: requestConversation, in: conversationID)
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
        sendTasks[id]?.cancel()
        sendTasks[id] = nil
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

    private func upsertAssistantMessage(
        id: UUID,
        in conversationID: UUID,
        text: String,
        thoughtSummary: String,
        status: ChatMessageStatus,
        fallbackCreatedAt: Date
    ) {
        mutateConversation(id: conversationID) { conversation in
            conversation.upsertMessage(
                ChatMessage(
                    id: id,
                    role: .assistant,
                    text: text,
                    thoughtSummary: thoughtSummary.nonEmptyTrimmed,
                    createdAt: conversation.messages.first(where: { $0.id == id })?.createdAt ?? fallbackCreatedAt,
                    status: status
                )
            )
        }
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

    private func persistDefaultConversationConfiguration() {
        defaults.set(defaultConversationConfiguration.model, forKey: DefaultsKeys.defaultConversationModel)
        defaults.set(
            defaultConversationConfiguration.thinkingIntensity.rawValue,
            forKey: DefaultsKeys.defaultConversationThinkingIntensity
        )
        defaults.set(
            defaultConversationConfiguration.customSystemPrompt ?? "",
            forKey: DefaultsKeys.defaultConversationSystemPrompt
        )
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

    private func shouldRetrySend(after error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if error is URLError {
            return true
        }

        if let error = error as? GeminiAPIError {
            switch error {
            case .missingAPIKey, .truncated:
                return false
            case .invalidResponse, .api, .emptyResponse, .incompleteResponse:
                return true
            }
        }

        if let error = error as? RelayAPIError {
            switch error {
            case .missingConfiguration, .truncated:
                return false
            case .invalidResponse, .remote, .emptyResponse, .incompleteResponse:
                return true
            }
        }

        return true
    }

    private func shouldRetryTranscription(after error: Error) -> Bool {
        if error is VoiceTranscriptionError {
            return false
        }

        return shouldRetrySend(after: error)
    }

    private func runSendTask(
        for conversationID: UUID,
        operation: @escaping @MainActor (ChatStore) async -> Void
    ) async {
        guard sendTasks[conversationID] == nil else {
            return
        }

        sendingConversationIDs.insert(conversationID)

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                self.sendTasks[conversationID] = nil
                self.sendingConversationIDs.remove(conversationID)
            }

            await operation(self)
        }

        sendTasks[conversationID] = task
        await task.value
    }

    private func retryLatestAssistantReply(in conversationID: UUID) async {
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

        guard let requestConversation = latestReplyRequestConversation(from: currentConversation) else {
            return
        }

        do {
            try await consumeActivationMessage(for: effectiveAIConfiguration.model)
        } catch {
            conversationErrors[conversationID] = error.localizedDescription
            return
        }

        conversationErrors[conversationID] = nil
        upsertConversation(requestConversation)
        await persist(requestConversation, sync: true)
        await streamAssistantReply(for: requestConversation, in: conversationID)
    }

    private func latestReplyRequestConversation(from conversation: ConversationThread) -> ConversationThread? {
        guard let lastUserIndex = conversation.messages.lastIndex(where: { $0.role == .user }) else {
            return nil
        }

        var requestConversation = conversation
        requestConversation.messages = Array(conversation.messages.prefix(lastUserIndex + 1))
        requestConversation.updatedAt = .now
        return requestConversation
    }

    private func consumeActivationMessage(for modelID: String) async throws {
        let nextActivationState = try OfflineActivation.consumeMessage(
            from: activationState,
            deviceToken: deviceIdentity.deviceToken,
            modelID: modelID
        )

        if nextActivationState != activationState {
            try await activationRepository.saveState(nextActivationState)
            activationState = nextActivationState
        }
    }

    private func streamAssistantReply(
        for requestConversation: ConversationThread,
        in conversationID: UUID
    ) async {
        guard var currentConversation = conversation(id: conversationID) else {
            return
        }

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

        let assistantMessageCreatedAt = Date.now
        upsertAssistantMessage(
            id: assistantMessageID,
            in: conversationID,
            text: "",
            thoughtSummary: "",
            status: .streaming,
            fallbackCreatedAt: assistantMessageCreatedAt
        )

        let maximumRetryCount = sendFailureRetryLimit
        var finalError: Error?
        var finalStreamedText = ""
        var finalStreamedThoughtSummary = ""
        var attemptCount = 0

        for attempt in 0...maximumRetryCount {
            attemptCount = attempt + 1

            do {
                if attempt > 0 {
                    upsertAssistantMessage(
                        id: assistantMessageID,
                        in: conversationID,
                        text: "",
                        thoughtSummary: "",
                        status: .streaming,
                        fallbackCreatedAt: assistantMessageCreatedAt
                    )

                    let delay = sendRetryDelayNanoseconds(attempt)
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: delay)
                    }
                }

                try Task.checkCancellation()

                let streamTask = Task { @MainActor () throws -> (String, String) in
                    var streamedText = ""
                    var streamedThoughtSummary = ""

                    for try await event in aiService.streamReply(for: requestConversation) {
                        try Task.checkCancellation()

                        switch event {
                        case .answerDelta(let delta):
                            streamedText.append(delta)
                        case .thoughtDelta(let delta):
                            streamedThoughtSummary.append(delta)
                        }

                        upsertAssistantMessage(
                            id: assistantMessageID,
                            in: conversationID,
                            text: streamedText,
                            thoughtSummary: streamedThoughtSummary,
                            status: .streaming,
                            fallbackCreatedAt: assistantMessageCreatedAt
                        )
                    }

                    return (streamedText, streamedThoughtSummary)
                }

                let (streamedText, streamedThoughtSummary) = try await withTaskCancellationHandler {
                    try await streamTask.value
                } onCancel: {
                    streamTask.cancel()
                }

                try Task.checkCancellation()

                upsertAssistantMessage(
                    id: assistantMessageID,
                    in: conversationID,
                    text: streamedText,
                    thoughtSummary: streamedThoughtSummary,
                    status: .sent,
                    fallbackCreatedAt: assistantMessageCreatedAt
                )

                if let finalizedConversation = conversation(id: conversationID) {
                    await persist(finalizedConversation, sync: true)
                }
                return
            } catch {
                finalError = error
                finalStreamedText = conversation(id: conversationID)?
                    .messages
                    .first(where: { $0.id == assistantMessageID })?
                    .text ?? ""
                finalStreamedThoughtSummary = conversation(id: conversationID)?
                    .messages
                    .first(where: { $0.id == assistantMessageID })?
                    .thoughtSummary ?? ""

                let hasRemainingRetries = attempt < maximumRetryCount
                guard hasRemainingRetries, shouldRetrySend(after: error) else {
                    break
                }
            }
        }

        guard let finalError else {
            return
        }

        if finalError is CancellationError == false {
            conversationErrors[conversationID] = failureMessage(
                from: finalError,
                automaticRetryCount: max(0, attemptCount - 1)
            )
        }

        mutateConversation(id: conversationID) { conversation in
            if finalStreamedText.isEmpty, finalStreamedThoughtSummary.isEmpty {
                conversation.removeMessage(id: assistantMessageID)
            } else {
                conversation.upsertMessage(
                    ChatMessage(
                        id: assistantMessageID,
                        role: .assistant,
                        text: finalStreamedText,
                        thoughtSummary: finalStreamedThoughtSummary.nonEmptyTrimmed,
                        createdAt: conversation.messages.first(where: { $0.id == assistantMessageID })?.createdAt ?? assistantMessageCreatedAt,
                        status: .failed
                    )
                )
            }
        }

        if let failedConversation = conversation(id: conversationID) {
            await persist(failedConversation, sync: true)
        }
    }

    private func failureMessage(
        from error: Error,
        automaticRetryCount: Int,
        operation: String? = nil
    ) -> String {
        guard automaticRetryCount > 0 else {
            return error.localizedDescription
        }

        if let operation {
            return "\(operation)已自动重试 \(automaticRetryCount) 次后仍失败：\(error.localizedDescription)"
        }

        return "已自动重试 \(automaticRetryCount) 次后仍失败：\(error.localizedDescription)"
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
        case .snapshot(let conversations):
            for remoteConversation in conversations {
                if let localConversation = conversation(id: remoteConversation.id),
                   localConversation.updatedAt > remoteConversation.updatedAt {
                    syncBridge.pushConversation(localConversation)
                    continue
                }

                upsertConversation(remoteConversation)
                await persist(remoteConversation, sync: false)
            }
        }
    }

    private static func makeDefaults(configuration: AppConfiguration) -> UserDefaults {
        if let appGroupIdentifier = configuration.appGroupIdentifier,
           let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            return defaults
        }

        return .standard
    }

    private static func loadSendFailureRetryLimit(from defaults: UserDefaults) -> Int {
        let storedValue = defaults.object(forKey: DefaultsKeys.sendFailureRetryLimit) as? Int
        let resolvedValue = storedValue ?? defaultSendFailureRetryLimit
        let normalizedValue = normalizedSendFailureRetryLimit(resolvedValue)

        defaults.set(normalizedValue, forKey: DefaultsKeys.sendFailureRetryLimit)
        return normalizedValue
    }

    private static func loadDefaultConversationConfiguration(
        from defaults: UserDefaults,
        fallbackModel: String
    ) -> ConversationAIConfiguration {
        let model = defaults.string(forKey: DefaultsKeys.defaultConversationModel)?.nonEmptyTrimmed ?? fallbackModel
        let storedThinkingIntensity = defaults.string(forKey: DefaultsKeys.defaultConversationThinkingIntensity)
            .flatMap(AIThinkingIntensity.init(rawValue:))
        let thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            storedThinkingIntensity ?? .balanced,
            for: model
        )
        let customSystemPrompt = defaults.string(forKey: DefaultsKeys.defaultConversationSystemPrompt)?.nonEmptyTrimmed

        defaults.set(model, forKey: DefaultsKeys.defaultConversationModel)
        defaults.set(thinkingIntensity.rawValue, forKey: DefaultsKeys.defaultConversationThinkingIntensity)
        defaults.set(customSystemPrompt ?? "", forKey: DefaultsKeys.defaultConversationSystemPrompt)

        return ConversationAIConfiguration(
            model: model,
            thinkingIntensity: thinkingIntensity,
            customSystemPrompt: customSystemPrompt
        )
    }

    private static func loadTranscriptionModel(
        from defaults: UserDefaults,
        fallbackModel: String
    ) -> String {
        let storedModel = defaults.string(forKey: DefaultsKeys.transcriptionModel)
        let resolvedModel = AITranscriptionModelCatalog.normalizedModel(
            storedModel ?? fallbackModel,
            defaultModel: fallbackModel
        )

        defaults.set(resolvedModel, forKey: DefaultsKeys.transcriptionModel)
        return resolvedModel
    }

    private static func loadTranscriptionCustomPrompt(from defaults: UserDefaults) -> String {
        let prompt = defaults.string(forKey: DefaultsKeys.transcriptionCustomPrompt) ?? ""
        defaults.set(prompt, forKey: DefaultsKeys.transcriptionCustomPrompt)
        return prompt
    }

    private static func loadTranscriptionIncludesContext(from defaults: UserDefaults) -> Bool {
        let includesContext: Bool

        if defaults.object(forKey: DefaultsKeys.transcriptionIncludesContext) == nil {
            includesContext = true
        } else {
            includesContext = defaults.bool(forKey: DefaultsKeys.transcriptionIncludesContext)
        }

        defaults.set(includesContext, forKey: DefaultsKeys.transcriptionIncludesContext)
        return includesContext
    }

    private static func normalizedSendFailureRetryLimit(_ value: Int) -> Int {
        min(max(value, minimumSendFailureRetryLimit), maximumSendFailureRetryLimit)
    }

    nonisolated private static func defaultSendRetryDelayNanoseconds(for attempt: Int) -> UInt64 {
        let boundedAttempt = min(max(attempt, 1), 3)
        return UInt64(boundedAttempt) * 500_000_000
    }
}

private enum DefaultsKeys {
    static let sendFailureRetryLimit = "chat.send_failure_retry_limit"
    static let defaultConversationModel = "chat.default_conversation_model"
    static let defaultConversationThinkingIntensity = "chat.default_conversation_thinking_intensity"
    static let defaultConversationSystemPrompt = "chat.default_conversation_system_prompt"
    static let transcriptionModel = "chat.transcription_model"
    static let transcriptionCustomPrompt = "chat.transcription_custom_prompt"
    static let transcriptionIncludesContext = "chat.transcription_includes_context"
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
        in conversation: ConversationThread,
        using configuration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        VoiceTranscriptionResult(
            text: "This is a preview voice transcript.",
            model: configuration.model
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
