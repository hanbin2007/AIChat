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

nonisolated enum DraftTextComposer {
    private static let sentencePunctuation = CharacterSet(charactersIn: ".?!。！？…")
    private static let clausePunctuation = CharacterSet(charactersIn: ",;:，；：")
    private static let leadingJoinPunctuation = CharacterSet(charactersIn: ".,;:!?%)]}，。！？；：、）】》」』'")

    static func appended(existing: String, addition: String) -> String {
        let normalizedAddition = normalizeSegment(addition)
        guard normalizedAddition.isEmpty == false else {
            return existing
        }

        let normalizedExisting = existing.trimmed
        guard normalizedExisting.isEmpty == false else {
            return normalizedAddition
        }

        return normalizedExisting + separatorBetween(existing: normalizedExisting, addition: normalizedAddition) + normalizedAddition
    }

    private static func normalizeSegment(_ text: String) -> String {
        text
            .collapseWhitespace()
            .replacingOccurrences(of: "\\s+([，。！？；：,.!?;:])", with: "$1", options: .regularExpression)
            .trimmed
    }

    private static func separatorBetween(existing: String, addition: String) -> String {
        guard let existingScalar = existing.unicodeScalars.last,
              let additionScalar = addition.unicodeScalars.first
        else {
            return " "
        }

        if CharacterSet.newlines.contains(existingScalar) || CharacterSet.newlines.contains(additionScalar) {
            return ""
        }

        if leadingJoinPunctuation.contains(additionScalar) {
            return ""
        }

        if sentencePunctuation.contains(existingScalar) || clausePunctuation.contains(existingScalar) {
            return needsInterWordSpace(before: existingScalar, after: additionScalar) ? " " : ""
        }

        if isCJK(existingScalar) && isCJK(additionScalar) {
            return "，"
        }

        return needsInterWordSpace(before: existingScalar, after: additionScalar) ? " " : ""
    }

    private static func needsInterWordSpace(
        before existingScalar: UnicodeScalar,
        after additionScalar: UnicodeScalar
    ) -> Bool {
        isLatinLike(existingScalar) && isLatinLike(additionScalar)
    }

    private static func isLatinLike(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FDF,
             0x3040...0x30FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0xFF66...0xFF9F:
            return true
        default:
            return false
        }
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
    @Published private(set) var syncStatus: CompanionSyncStatus
    @Published private(set) var syncStatusDescription: String
    @Published private(set) var activationState: OfflineActivationState?
    @Published private(set) var pairedWatchActivationRequestCode: String?
    @Published private(set) var companionActivationFeedbackMessage: String?
    @Published private(set) var sendFailureRetryLimit: Int
    @Published private(set) var defaultConversationConfiguration: ConversationAIConfiguration
    @Published private(set) var transcriptionModel: String
    @Published private(set) var transcriptionCustomPrompt: String
    @Published private(set) var transcriptionIncludesContext: Bool
    @Published private(set) var globalPinnedMemories: [PinnedMemoryItem] = []
    @Published private(set) var promptPresets: [PromptPreset] = PromptPreset.builtInPresets

    let configuration: AppConfiguration
    let storageDescription: String
    let deviceIdentity: WatchDeviceIdentity

    private let repository: ConversationRepository
    private let aiService: AIStreamingService
    private let transcriptionService: AITranscriptionService?
    private let memoryMaintenanceService: any AIMemoryMaintenanceService
    private let syncBridge: CompanionSyncBridge
    private let activationRepository: ActivationRepository
    private let defaults: UserDefaults
    private let sendRetryDelayNanoseconds: @Sendable (Int) -> UInt64
    @Published private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false
    private var sendTasks: [UUID: Task<Void, Never>] = [:]
    private var lastHandledCompanionActivationTransferID: String?

    init(
        repository: ConversationRepository,
        aiService: AIStreamingService,
        transcriptionService: AITranscriptionService?,
        memoryMaintenanceService: any AIMemoryMaintenanceService = HeuristicMemoryMaintenanceService(),
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
        self.memoryMaintenanceService = memoryMaintenanceService
        self.configuration = configuration
        self.syncBridge = syncBridge
        self.activationRepository = activationRepository
        self.deviceIdentity = deviceIdentity ?? WatchDeviceIdentityProvider.current()
        self.defaults = resolvedDefaults
        self.sendRetryDelayNanoseconds = sendRetryDelayNanoseconds
        self.storageDescription = repository.storageDescription
        self.syncStatus = syncBridge.currentStatus
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
            self?.syncStatus = status
            self?.syncStatusDescription = status.description
        }

        syncBridge.setSnapshotProvider { [weak self] in
            self?.conversations ?? []
        }

        syncBridge.setGlobalPinnedMemoriesProvider { [weak self] in
            self?.globalPinnedMemories ?? []
        }

        syncBridge.setPromptPresetsProvider { [weak self] in
            self?.promptPresets ?? PromptPreset.builtInPresets
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
            return L10n.tr("activation.status.inactive")
        case .pending:
            return L10n.tr("activation.status.pending")
        case .active:
            return L10n.tr("activation.status.active")
        case .expired:
            return L10n.tr("activation.status.expired")
        case .exhausted:
            return L10n.tr("activation.status.exhausted")
        case .invalid:
            return L10n.tr("activation.status.invalid")
        }
    }

    var activationStatusMessage: String {
        switch activationStatus {
        case .inactive:
            return L10n.tr("activation.message.inactive")
        case .pending(let state):
            return OfflineActivationError.notYetActive(startDate: state.license.validFrom).localizedDescription
        case .active(let state, let remainingMessages):
            var components: [String] = []
            if let validUntil = state.license.validUntil {
                components.append(
                    L10n.format(
                        "activation.message.active.valid_until",
                        validUntil.formatted(date: .abbreviated, time: .shortened)
                    )
                )
            } else {
                components.append(L10n.tr("activation.message.active.forever"))
            }

            if let remainingMessages {
                components.append(L10n.format("activation.message.active.remaining", remainingMessages))
            } else {
                components.append(L10n.tr("activation.message.active.unlimited"))
            }

            components.append(
                L10n.format(
                    "activation.message.active.models",
                    allowedModelsDescription(for: state.license.allowedModelIDs)
                )
            )
            return components.joined(separator: " • ")
        case .expired(let state):
            if let validUntil = state.license.validUntil {
                return L10n.format(
                    "activation.message.expired.with_date",
                    validUntil.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return L10n.tr("activation.message.expired.no_date")
        case .exhausted(let state):
            return L10n.format(
                "activation.message.exhausted",
                state.license.messageLimit ?? 0
            )
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
            globalPinnedMemories = try await repository.loadGlobalPinnedMemories()
            promptPresets = PromptPreset.resolvedLibrary(from: try await repository.loadPromptPresets())
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

    func publishActivationRequestCodeToCompanion(_ requestCode: String) {
        syncBridge.pushActivationRequestCode(requestCode)
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

    var canTransferActivationCodeToPairedWatch: Bool {
        switch syncStatus {
        case .idle, .reachable:
            return true
        case .unavailable, .notPaired, .companionMissing:
            return false
        }
    }

    func sendActivationCodeToPairedWatch(_ rawCode: String) {
        syncBridge.pushActivationCodeImport(rawCode)
    }

    func clearCompanionActivationFeedbackMessage() {
        companionActivationFeedbackMessage = nil
    }

    func createConversation() async -> UUID {
        let conversation = ConversationThread.empty(
            aiConfiguration: defaultConversationConfiguration
        )
        upsertConversation(conversation)
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

    var favoriteConversations: [ConversationThread] {
        conversations.filter(\.isFavorite)
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

    var appVersionDescription: String {
        Bundle.main.appVersionDescription
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

    func updateUsesGlobalPinnedMemory(
        _ usesGlobalPinnedMemory: Bool,
        for conversationID: UUID
    ) async {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.usesGlobalPinnedMemory = usesGlobalPinnedMemory
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

    func promptPreset(id: UUID) -> PromptPreset? {
        promptPresets.first { $0.id == id }
    }

    func promptPresets(of kind: PromptPresetKind) -> [PromptPreset] {
        promptPresets.filter { $0.kind == kind }
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

    func setConversationFavorite(
        _ isFavorite: Bool,
        for conversationID: UUID
    ) async {
        guard var conversation = conversation(id: conversationID),
              conversation.isFavorite != isFavorite
        else {
            return
        }

        conversation.updateFavorite(isFavorite)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    func createPromptPreset(
        kind: PromptPresetKind,
        title: String,
        content: String
    ) async {
        let normalizedTitle = title.nonEmptyTrimmed
        let normalizedContent = content.nonEmptyTrimmed
        guard let normalizedTitle, let normalizedContent else {
            return
        }

        let preset = PromptPreset(
            kind: kind,
            title: normalizedTitle,
            content: normalizedContent
        )
        promptPresets = PromptPreset.resolvedLibrary(from: promptPresets + [preset])
        await persistPromptPresets(sync: true)
    }

    func updatePromptPreset(
        id presetID: UUID,
        kind: PromptPresetKind,
        title: String,
        content: String
    ) async {
        guard let existingPreset = promptPreset(id: presetID),
              existingPreset.isBuiltIn == false,
              let normalizedTitle = title.nonEmptyTrimmed,
              let normalizedContent = content.nonEmptyTrimmed
        else {
            return
        }

        let updatedPreset = existingPreset.updated(
            kind: kind,
            title: normalizedTitle,
            content: normalizedContent
        )
        promptPresets = PromptPreset.resolvedLibrary(
            from: promptPresets.map { $0.id == presetID ? updatedPreset : $0 }
        )
        await persistPromptPresets(sync: true)
    }

    func deletePromptPreset(id presetID: UUID) async {
        guard let existingPreset = promptPreset(id: presetID),
              existingPreset.isBuiltIn == false
        else {
            return
        }

        promptPresets = PromptPreset.resolvedLibrary(
            from: promptPresets.filter { $0.id != presetID }
        )
        await persistPromptPresets(sync: true)
    }

    func pinMessage(
        id messageID: UUID,
        from conversationID: UUID,
        scope: PinnedMemoryScope
    ) async {
        guard let conversation = conversation(id: conversationID),
              let message = conversation.messages.first(where: { $0.id == messageID }),
              let text = message.cleanedText.nonEmptyTrimmed
        else {
            return
        }

        let item = PinnedMemoryItem(
            text: String(text.prefix(260)),
            keywords: derivedKeywords(from: text),
            scope: scope,
            sourceMessageIDs: [messageID],
            updatedAt: .now
        )

        switch scope {
        case .conversation:
            guard conversation.pinnedMemories.contains(where: { $0.text == item.text }) == false else {
                return
            }

            mutateConversation(id: conversationID) { updatedConversation in
                updatedConversation.pinnedMemories.append(item)
            }
            if let updatedConversation = self.conversation(id: conversationID) {
                await persist(updatedConversation, sync: true)
            }
        case .global:
            guard globalPinnedMemories.contains(where: { $0.text == item.text }) == false else {
                return
            }

            globalPinnedMemories.append(item)
            await persistGlobalPinnedMemories(sync: true)
        }
    }

    func removePinnedMemory(
        id pinnedMemoryID: UUID,
        from conversationID: UUID
    ) async {
        guard let currentConversation = conversation(id: conversationID),
              currentConversation.pinnedMemories.contains(where: { $0.id == pinnedMemoryID })
        else {
            return
        }

        mutateConversation(id: conversationID) { updatedConversation in
            updatedConversation.replacePinnedMemories(
                updatedConversation.pinnedMemories.filter { $0.id != pinnedMemoryID }
            )
        }

        if let updatedConversation = conversation(id: conversationID) {
            await persist(updatedConversation, sync: true)
        }
    }

    func removeGlobalPinnedMemory(id pinnedMemoryID: UUID) async {
        let filteredMemories = globalPinnedMemories.filter { $0.id != pinnedMemoryID }
        guard filteredMemories.count != globalPinnedMemories.count else {
            return
        }

        globalPinnedMemories = filteredMemories
        await persistGlobalPinnedMemories(sync: true)
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
              let storedConversation = conversation(id: conversationID)
        else {
            return
        }

        let currentConversation = requestConversation(from: storedConversation)

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
            includesContext: isTranscriptionContextEnabled,
            existingDraftText: drafts[conversationID]?.text ?? ""
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
                draft.text = appendedDraftText(
                    existing: draft.text,
                    addition: transcription.text
                )
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
                operation: L10n.tr("operation.voice_transcription")
            )
        }
    }

    func sendRecordedAudioDirectly(_ audioAttachment: ChatAttachment, in conversationID: UUID) async {
        guard audioAttachment.isAudio else {
            conversationErrors[conversationID] = VoiceTranscriptionError.invalidAudio.localizedDescription
            return
        }

        guard isSending(conversationID: conversationID) == false,
              isTranscribing(conversationID: conversationID) == false
        else {
            return
        }

        let draft = ConversationDraft(text: "", attachments: [audioAttachment])
        await runSendTask(for: conversationID) { store in
            await store.send(draft: draft, in: conversationID, clearStoredDraft: false)
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

        let requestConversation = requestConversation(from: currentConversation)
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

    private func persistGlobalPinnedMemories(sync: Bool) async {
        do {
            try await repository.saveGlobalPinnedMemories(globalPinnedMemories)
            if sync {
                syncBridge.pushGlobalPinnedMemories(globalPinnedMemories)
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func persistPromptPresets(sync: Bool) async {
        do {
            try await repository.savePromptPresets(promptPresets)
            if sync {
                syncBridge.pushPromptPresets(promptPresets)
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
        conversations.append(conversation)
        conversations.sort(by: ConversationThread.sortsByMostRecentFirst)
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

        guard let latestReplyConversation = latestReplyRequestConversation(from: currentConversation) else {
            return
        }
        let requestConversation = requestConversation(from: latestReplyConversation)

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

    private func refreshConversationArtifacts(for conversationID: UUID) async {
        guard var conversation = conversation(id: conversationID) else {
            return
        }

        let derivedArtifacts = await memoryMaintenanceService.refreshArtifacts(for: conversation)

        if conversation.focusState == derivedArtifacts.focusState,
           conversation.memoryItems == derivedArtifacts.memoryItems,
           conversation.archiveSegments == derivedArtifacts.archiveSegments {
            return
        }

        conversation.updateFocusState(derivedArtifacts.focusState)
        conversation.replaceMemoryItems(derivedArtifacts.memoryItems)
        conversation.replaceArchiveSegments(derivedArtifacts.archiveSegments)
        upsertConversation(conversation)
        await persist(conversation, sync: true)
    }

    private func contextEligibleMessages(in conversation: ConversationThread) -> [ChatMessage] {
        conversation.messages.filter { message in
            message.status != .failed &&
            message.role != .system &&
            message.hasVisibleContent
        }
    }

    private func deriveFocusState(
        from messages: [ChatMessage],
        existingFocusState: ConversationFocusState?,
        mode: ContextMode,
        conversationTitle: String
    ) -> ConversationFocusState? {
        guard messages.isEmpty == false else {
            return nil
        }

        if mode == .casual, let existingFocusState, existingFocusState.openLoops.isEmpty {
            return nil
        }

        let focusMessages = Array(messages.suffix(mode == .casual ? 4 : 6))
        let latestFocusTitleSource = focusMessages.reversed().first { message in
            message.role == .user && message.cleanedText.isEmpty == false
        }?.cleanedText
        let title = latestFocusTitleSource.map { source in
            String(source.prefix(28)).trimmed
        } ?? existingFocusState?.title ?? conversationTitle

        let focusLines = focusMessages.map { message in
            let speaker = message.role == .assistant ? "Assistant" : "User"
            return "\(speaker): \(message.cleanedText.collapseWhitespace())"
        }
        let focusNote = focusLines.joined(separator: "\n")
        let openLoops = extractOpenLoops(from: focusMessages)
        let sourceMessageIDs = focusMessages.map(\.id)

        guard focusNote.nonEmptyTrimmed != nil || openLoops.isEmpty == false else {
            return nil
        }

        return ConversationFocusState(
            id: existingFocusState?.id ?? UUID(),
            kind: mode,
            title: String(title),
            focusNote: String(focusNote.prefix(1_500)),
            openLoops: openLoops,
            sourceMessageIDs: sourceMessageIDs,
            updatedAt: .now
        )
    }

    private func deriveMemoryItems(from messages: [ChatMessage]) -> [ConversationMemoryItem] {
        let candidates = messages
            .filter { $0.role == .user }
            .dropLast(2)
            .compactMap(\.cleanedText.nonEmptyTrimmed)
            .filter { text in
                let normalized = text.lowercased()
                return [
                    "喜欢", "希望", "请用", "尽量", "不要", "习惯", "更喜欢",
                    "薄弱", "容易错", "总是错", "看不懂", "中文", "分步", "详细"
                ].contains(where: { normalized.contains($0) })
            }

        var uniqueTexts: [String] = []
        for candidate in candidates.reversed() {
            if uniqueTexts.contains(candidate) == false {
                uniqueTexts.append(candidate)
            }
            if uniqueTexts.count >= 8 {
                break
            }
        }

        return uniqueTexts.map { text in
            ConversationMemoryItem(
                text: String(text.prefix(220)),
                keywords: derivedKeywords(from: text)
            )
        }
    }

    private func deriveArchiveSegments(
        from messages: [ChatMessage],
        existingSegments: [ConversationArchiveSegment],
        protectedRecentMessages: Int
    ) -> [ConversationArchiveSegment] {
        guard messages.count > 14 || messages.reduce(0, { $0 + max($1.cleanedText.count, 24) }) > 8_000 else {
            return existingSegments
        }

        let protectedIDs = Set(messages.suffix(protectedRecentMessages).map(\.id))
        let archivedMessageIDs = Set(existingSegments.flatMap(\.sourceMessageIDs))
        let candidateMessages = messages.filter { message in
            protectedIDs.contains(message.id) == false &&
            archivedMessageIDs.contains(message.id) == false
        }

        guard candidateMessages.isEmpty == false else {
            return existingSegments
        }

        let segmentMessages = Array(candidateMessages.prefix(8))
        let summary = summarizedArchiveText(for: segmentMessages)
        guard summary.isEmpty == false else {
            return existingSegments
        }

        let archiveTitleSource = segmentMessages.first { message in
            message.role == .user && message.cleanedText.isEmpty == false
        }?.cleanedText
        let title = archiveTitleSource.map { source in
            String(source.prefix(28)).trimmed
        } ?? "Archived Context"
        let sourceMessageIDs = segmentMessages.map(\.id)
        if existingSegments.contains(where: { $0.sourceMessageIDs == sourceMessageIDs }) {
            return existingSegments
        }

        var updatedSegments = existingSegments
        updatedSegments.append(
            ConversationArchiveSegment(
                title: String(title),
                summary: summary,
                keywords: derivedKeywords(from: summary),
                openLoops: extractOpenLoops(from: segmentMessages),
                sourceMessageIDs: sourceMessageIDs,
                updatedAt: .now
            )
        )

        return Array(updatedSegments.suffix(24))
    }

    private func extractOpenLoops(from messages: [ChatMessage]) -> [String] {
        var loops: [String] = []

        for message in messages.reversed() where message.role == .user {
            guard let text = message.cleanedText.nonEmptyTrimmed else {
                continue
            }

            let normalized = text.lowercased()
            let isOpenLoop =
                text.contains("?") ||
                text.contains("？") ||
                normalized.contains("下一步") ||
                normalized.contains("继续") ||
                normalized.contains("为什么") ||
                normalized.contains("怎么")

            guard isOpenLoop else {
                continue
            }

            loops.append(String(text.prefix(140)))
            if loops.count >= 3 {
                break
            }
        }

        return loops.reversed()
    }

    private func summarizedArchiveText(for messages: [ChatMessage]) -> String {
        String(
            messages
            .compactMap { message -> String? in
                guard let text = message.cleanedText.nonEmptyTrimmed else {
                    return nil
                }
                let speaker = message.role == .assistant ? "Assistant" : "User"
                return "\(speaker): \(text.collapseWhitespace())"
            }
            .joined(separator: "\n")
            .prefix(1_200)
        ).trimmed
    }

    private func derivedKeywords(from text: String) -> [String] {
        let normalized = text.collapseWhitespace().lowercased()
        let wordMatches = normalized.matches(for: #"[a-z0-9_]{2,}"#)
        let cjkTokens = normalized.cjkBigrams()
        return Array(Set((wordMatches + cjkTokens).filter { $0.isEmpty == false })).sorted().prefix(12).map { $0 }
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
                    let flushInterval: TimeInterval = 0.05
                    var lastFlushAt = Date.distantPast
                    var hasFlushedVisibleContent = false

                    @MainActor
                    func flushIfNeeded(force: Bool = false) {
                        let now = Date.now
                        guard force || hasFlushedVisibleContent == false || now.timeIntervalSince(lastFlushAt) >= flushInterval else {
                            return
                        }

                        upsertAssistantMessage(
                            id: assistantMessageID,
                            in: conversationID,
                            text: streamedText,
                            thoughtSummary: streamedThoughtSummary,
                            status: .streaming,
                            fallbackCreatedAt: assistantMessageCreatedAt
                        )

                        lastFlushAt = now
                        hasFlushedVisibleContent = true
                    }

                    for try await event in aiService.streamReply(for: requestConversation) {
                        try Task.checkCancellation()

                        switch event {
                        case .answerDelta(let delta):
                            streamedText.append(delta)
                        case .thoughtDelta(let delta):
                            streamedThoughtSummary.append(delta)
                        }

                        flushIfNeeded(force: hasFlushedVisibleContent == false)
                    }

                    flushIfNeeded(force: true)

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
                    await refreshConversationArtifacts(for: conversationID)
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
        let errorDescription = detailedErrorDescription(for: error)

        guard automaticRetryCount > 0 else {
            return errorDescription
        }

        if let operation {
            let localizedFormat = L10n.tr("error.retry.failure_with_operation")
            if localizedFormat == "error.retry.failure_with_operation" {
                return "\(operation) failed after \(automaticRetryCount) retries: \(errorDescription)"
            }

            return String(
                format: localizedFormat,
                locale: Locale.current,
                arguments: [operation, automaticRetryCount, errorDescription]
            )
        }

        let localizedFormat = L10n.tr("error.retry.failure")
        if localizedFormat == "error.retry.failure" {
            return "Still failed after \(automaticRetryCount) retries: \(errorDescription)"
        }

        return String(
            format: localizedFormat,
            locale: Locale.current,
            arguments: [automaticRetryCount, errorDescription]
        )
    }

    private func detailedErrorDescription(for error: Error) -> String {
        let nsError = error as NSError
        let localizedDescription = nsError.localizedDescription.nonEmptyTrimmed ?? String(describing: error)
        let debugSuffix = "(\(nsError.domain) \(nsError.code))"

        if localizedDescription.contains(debugSuffix) {
            return localizedDescription
        }

        return "\(localizedDescription) \(debugSuffix)"
    }

    private func appendedDraftText(existing: String, addition: String) -> String {
        DraftTextComposer.appended(existing: existing, addition: addition)
    }

    private func allowedModelsDescription(for allowedModelIDs: Set<String>?) -> String {
        guard let allowedModelIDs else {
            return L10n.tr("common.all")
        }

        let titles = LicensedModelCatalog.supportedModels
            .filter { allowedModelIDs.contains($0.id) }
            .map(\.title)

        return titles.isEmpty ? L10n.tr("common.all") : titles.joined(separator: L10n.tr("list.separator"))
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
        case .globalPinnedMemories(let items):
            await mergeGlobalPinnedMemories(items, syncMergedState: true)
        case .promptPresets(let presets):
            await replacePromptPresets(presets, syncMergedState: false)
        case .activationRequestCode(let requestCode):
            #if os(iOS)
            pairedWatchActivationRequestCode = OfflineActivation.formatForDisplay(requestCode, groupSize: 4)
            #endif
        case .activationCodeImport(let code, let transferID):
            #if os(watchOS)
            if let transferID, transferID == lastHandledCompanionActivationTransferID {
                return
            }

            lastHandledCompanionActivationTransferID = transferID
            let normalizedCode = OfflineActivation.normalizeActivationInput(code)

            do {
                try await applyActivationCode(normalizedCode)
                companionActivationFeedbackMessage = L10n.tr("activation.import.success")
            } catch {
                companionActivationFeedbackMessage = L10n.format(
                    "activation.import.failure",
                    error.localizedDescription
                )
            }
            #endif
        }
    }

    private func mergeGlobalPinnedMemories(
        _ incomingItems: [PinnedMemoryItem],
        syncMergedState: Bool
    ) async {
        var itemsByID = Dictionary(uniqueKeysWithValues: globalPinnedMemories.map { ($0.id, $0) })

        for item in incomingItems {
            if let existing = itemsByID[item.id], existing.updatedAt >= item.updatedAt {
                continue
            }

            itemsByID[item.id] = item
        }

        let mergedItems = itemsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }

        guard mergedItems != globalPinnedMemories else {
            return
        }

        globalPinnedMemories = mergedItems
        await persistGlobalPinnedMemories(sync: syncMergedState)
    }

    private func replacePromptPresets(
        _ incomingPresets: [PromptPreset],
        syncMergedState: Bool
    ) async {
        let resolvedPresets = PromptPreset.resolvedLibrary(from: incomingPresets)
        guard resolvedPresets != promptPresets else {
            return
        }

        promptPresets = resolvedPresets
        await persistPromptPresets(sync: syncMergedState)
    }

    private func requestConversation(from conversation: ConversationThread) -> ConversationThread {
        let resolvedConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        guard resolvedConfiguration.usesGlobalPinnedMemory else {
            return conversation
        }

        let existingIDs = Set(conversation.pinnedMemories.map(\.id))
        let additionalPinnedMemories = globalPinnedMemories.filter { existingIDs.contains($0.id) == false }
        guard additionalPinnedMemories.isEmpty == false else {
            return conversation
        }

        var enrichedConversation = conversation
        enrichedConversation.pinnedMemories.append(contentsOf: additionalPinnedMemories)
        return enrichedConversation
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

        store.conversations = conversations.sorted(by: ConversationThread.sortsByMostRecentFirst)
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
