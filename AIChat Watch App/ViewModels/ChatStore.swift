//
//  ChatStore.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Combine
import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

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

nonisolated enum RelayStorePurchaseOutcome: Equatable, Sendable {
    case completed
    case pending
    case cancelled
}

protocol ReplyPersistenceControlling: AnyObject {
    func beginStreamingReplyPersistence() -> UUID
    func endStreamingReplyPersistence(_ token: UUID)
}

final class NoopReplyPersistenceController: ReplyPersistenceControlling {
    func beginStreamingReplyPersistence() -> UUID {
        UUID()
    }

    func endStreamingReplyPersistence(_ token: UUID) {}
}

final class DeviceReplyPersistenceController: NSObject, ReplyPersistenceControlling {
    private let stateLock = NSCondition()
    private var activeTokens: Set<UUID> = []

    #if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #elseif os(watchOS)
    private var extendedRuntimeSession: WKExtendedRuntimeSession?
    private var expiringActivityIsRunning = false
    #endif

    func beginStreamingReplyPersistence() -> UUID {
        let token = UUID()
        stateLock.lock()
        let shouldActivate = activeTokens.isEmpty
        activeTokens.insert(token)
        stateLock.unlock()

        if shouldActivate {
            activateIfPossible()
        }

        return token
    }

    func endStreamingReplyPersistence(_ token: UUID) {
        stateLock.lock()
        guard activeTokens.remove(token) != nil else {
            stateLock.unlock()
            return
        }

        let shouldDeactivate = activeTokens.isEmpty
        stateLock.broadcast()
        stateLock.unlock()

        if shouldDeactivate {
            deactivate()
        }
    }

    private func activateIfPossible() {
        guard Self.isRunningUnitTests == false else {
            return
        }

        #if os(iOS)
        guard backgroundTaskIdentifier == .invalid else {
            return
        }

        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
            withName: "AIChatAssistantReply"
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handleExpiration()
            }
        }
        #elseif os(watchOS)
        activateExpiringActivityIfPossible()
        activateExtendedRuntimeSessionIfPossible()
        #endif
    }

    private func deactivate() {
        #if os(iOS)
        guard backgroundTaskIdentifier != .invalid else {
            return
        }

        let taskIdentifier = backgroundTaskIdentifier
        backgroundTaskIdentifier = .invalid
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        #elseif os(watchOS)
        extendedRuntimeSession?.invalidate()
        extendedRuntimeSession = nil
        stateLock.lock()
        stateLock.broadcast()
        stateLock.unlock()
        #endif
    }

    private func handleExpiration() {
        #if os(iOS)
        deactivate()
        #endif
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    #if os(watchOS)
    private func activateExtendedRuntimeSessionIfPossible() {
        guard extendedRuntimeSession == nil,
              WKExtension.shared().applicationState == .active
        else {
            return
        }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        extendedRuntimeSession = session
        session.start()
    }

    private func activateExpiringActivityIfPossible() {
        stateLock.lock()
        guard expiringActivityIsRunning == false else {
            stateLock.unlock()
            return
        }

        expiringActivityIsRunning = true
        stateLock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ProcessInfo.processInfo.performExpiringActivity(withReason: "AIChatAssistantReply") { expired in
                guard let self else {
                    return
                }

                self.stateLock.lock()
                defer {
                    self.expiringActivityIsRunning = false
                    self.stateLock.broadcast()
                    self.stateLock.unlock()
                }

                while self.activeTokens.isEmpty == false, expired == false {
                    self.stateLock.wait(until: Date(timeIntervalSinceNow: 0.25))
                }
            }
        }
    }
    #endif
}

#if os(watchOS)
extension DeviceReplyPersistenceController: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        guard self.extendedRuntimeSession === extendedRuntimeSession else {
            return
        }

        self.extendedRuntimeSession = nil
    }
}
#endif

nonisolated enum RecoveredStreamingMessageNormalizer {
    static func normalized(conversation: ConversationThread) -> (conversation: ConversationThread, didChange: Bool) {
        var normalizedConversation = conversation
        var normalizedMessages: [ChatMessage] = []
        normalizedMessages.reserveCapacity(conversation.messages.count)
        var didChange = false

        for message in conversation.messages {
            guard message.role == .assistant, message.status == .streaming else {
                normalizedMessages.append(message)
                continue
            }

            let hasRecoverableContent =
                message.cleanedText.isEmpty == false ||
                message.cleanedThoughtSummary != nil ||
                message.cleanedModelResponseParts != nil ||
                message.attachments.isEmpty == false

            if hasRecoverableContent {
                var recoveredMessage = message
                recoveredMessage.status = .failed
                normalizedMessages.append(recoveredMessage)
            } else {
                didChange = true
                continue
            }

            didChange = true
        }

        guard didChange else {
            return (conversation, false)
        }

        normalizedConversation.messages = normalizedMessages
        return (normalizedConversation, true)
    }
}

private struct AssistantReplyStreamingSnapshot: Sendable {
    var text = ""
    var thoughtSummary = ""
    var modelResponseParts: [GeminiPartPayload]?
    var attachments: [ChatAttachment] = []
}

private nonisolated func collectAssistantReplyStream(
    from stream: AsyncThrowingStream<AIStreamEvent, Error>,
    flushInterval: TimeInterval,
    persistenceInterval: TimeInterval,
    onFlush: @escaping @MainActor (_ snapshot: AssistantReplyStreamingSnapshot, _ shouldPersist: Bool) async -> Void
) async throws -> AssistantReplyStreamingSnapshot {
    var snapshot = AssistantReplyStreamingSnapshot()
    var lastFlushAt = Date.distantPast
    var lastPersistAt = Date.distantPast
    var hasFlushedVisibleContent = false
    var hasPersistedStreamingProgress = false

    func flushIfNeeded(force: Bool = false) async {
        let now = Date.now
        let shouldFlushVisibleContent =
            force ||
            hasFlushedVisibleContent == false ||
            now.timeIntervalSince(lastFlushAt) >= flushInterval
        let shouldPersistStreamingProgress =
            force ||
            hasPersistedStreamingProgress == false ||
            now.timeIntervalSince(lastPersistAt) >= persistenceInterval

        guard shouldFlushVisibleContent || shouldPersistStreamingProgress else {
            return
        }

        await onFlush(snapshot, shouldPersistStreamingProgress)

        if shouldFlushVisibleContent {
            lastFlushAt = now
            hasFlushedVisibleContent = true
        }

        if shouldPersistStreamingProgress {
            lastPersistAt = now
            hasPersistedStreamingProgress = true
        }
    }

    for try await event in stream {
        try Task.checkCancellation()

        switch event {
        case .answerDelta(let delta):
            snapshot.text.append(delta)
        case .thoughtDelta(let delta):
            snapshot.thoughtSummary.append(delta)
        case .modelResponseParts(let modelResponseParts):
            snapshot.modelResponseParts = modelResponseParts
        case .attachment(let attachment):
            guard snapshot.attachments.contains(where: {
                $0.mimeType == attachment.mimeType && $0.data == attachment.data
            }) == false else {
                continue
            }

            snapshot.attachments.append(attachment)
        }

        await flushIfNeeded(force: hasFlushedVisibleContent == false)
    }

    await flushIfNeeded(force: true)

    return snapshot
}

@MainActor
final class ChatStore: ObservableObject {
    static let defaultSendFailureRetryLimit = 3
    static let maximumSendFailureRetryLimit = 10
    static let minimumSendFailureRetryLimit = 1
    static let streamingProgressPersistenceInterval: TimeInterval = 1

    @Published private(set) var conversations: [ConversationThread] = []
    @Published private(set) var conversationListItems: [WatchConversationListItem] = []
    @Published private(set) var favoriteConversationListItems: [WatchConversationListItem] = []
    @Published private(set) var startupError: String?
    @Published private(set) var sendingConversationIDs: Set<UUID> = []
    @Published private(set) var transcribingConversationIDs: Set<UUID> = []
    @Published private(set) var conversationErrors: [UUID: String] = [:]
    @Published private(set) var syncStatus: CompanionSyncStatus
    @Published private(set) var syncStatusDescription: String
    @Published private(set) var activationState: OfflineActivationState?
    @Published private(set) var relayAccountStatus: RelayAccountStatusResponse?
    @Published private(set) var relayCatalog: RelayCatalogResponse?
    @Published private(set) var relayBillingBusy = false
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
    private let completionFeedbackProvider: any CompletionFeedbackProviding
    private let memoryMaintenanceService: any AIMemoryMaintenanceService
    private let syncBridge: CompanionSyncBridge
    private let replyPersistenceController: any ReplyPersistenceControlling
    private let cloudSyncService: ICloudConversationSyncService?
    private let activationRepository: ActivationRepository
    private let relayAccessRepository: RelayAccessRepository
    private let relayAccountService: RelayAccountService
    private let defaults: UserDefaults
    private let sendRetryDelayNanoseconds: @Sendable (Int) -> UInt64
    @Published private var drafts: [UUID: ConversationDraft] = [:]
    private var hasLoadedConversations = false
    private var conversationIndexByID: [UUID: Int] = [:]
    private var sendTasks: [UUID: Task<Void, Never>] = [:]
    private var lastHandledCompanionActivationTransferID: String?
    private var deletedConversationTombstones: [UUID: Date] = [:]
    private var lastPushedSyncSummaryDigest: String?
    private var lastBootstrapRequestAt: Date?

    init(
        repository: ConversationRepository,
        aiService: AIStreamingService,
        transcriptionService: AITranscriptionService?,
        completionFeedbackProvider: (any CompletionFeedbackProviding)? = nil,
        memoryMaintenanceService: any AIMemoryMaintenanceService = HeuristicMemoryMaintenanceService(),
        configuration: AppConfiguration,
        syncBridge: CompanionSyncBridge,
        replyPersistenceController: (any ReplyPersistenceControlling)? = nil,
        cloudSyncService: ICloudConversationSyncService? = nil,
        activationRepository: ActivationRepository? = nil,
        deviceIdentity: WatchDeviceIdentity? = nil,
        defaults: UserDefaults? = nil,
        sendRetryDelayNanoseconds: @escaping @Sendable (Int) -> UInt64 = ChatStore.defaultSendRetryDelayNanoseconds
    ) {
        let resolvedDefaults = defaults ?? Self.makeDefaults(configuration: configuration)
        let resolvedActivationRepository = activationRepository ??
            ActivationRepository(configuration: configuration, rootURL: repository.resolvedRootURL)
        self.repository = repository
        self.aiService = aiService
        self.transcriptionService = transcriptionService
        self.completionFeedbackProvider =
            completionFeedbackProvider ?? DeviceCompletionFeedbackProvider()
        self.memoryMaintenanceService = memoryMaintenanceService
        self.configuration = configuration
        self.syncBridge = syncBridge
        self.replyPersistenceController = replyPersistenceController ?? DeviceReplyPersistenceController()
        self.cloudSyncService = cloudSyncService
        self.activationRepository = resolvedActivationRepository
        self.deviceIdentity = deviceIdentity ??
            WatchDeviceIdentityProvider.current(activationRepository: resolvedActivationRepository)
        self.relayAccessRepository = RelayAccessRepository(
            configuration: configuration,
            rootURL: repository.resolvedRootURL
        )
        self.relayAccountService = RelayAccountService(
            configuration: configuration,
            deviceIdentity: self.deviceIdentity,
            repository: self.relayAccessRepository
        )
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
            guard let self else {
                return
            }

            self.syncStatus = status
            self.syncStatusDescription = status.description

            Task { @MainActor [weak self] in
                await self?.handleSyncStatusChange(status)
            }
        }

        syncBridge.setSnapshotProvider { [weak self] in
            self?.conversations ?? []
        }

        let attachmentsDirectoryURL = repository.attachmentsDirectoryURL
        syncBridge.setAttachmentFileURLProvider { blobFilename in
            attachmentsDirectoryURL.appendingPathComponent(blobFilename, isDirectory: false)
        }

        syncBridge.setDeletedConversationTombstonesProvider { [weak self] in
            self?.deletedConversationTombstones.map {
                CompanionDeletedConversationTombstone(id: $0.key, deletedAt: $0.value)
            } ?? []
        }

        syncBridge.setGlobalPinnedMemoriesProvider { [weak self] in
            self?.globalPinnedMemories ?? []
        }

        syncBridge.setPromptPresetsProvider { [weak self] in
            self?.promptPresets ?? PromptPreset.builtInPresets
        }

        syncBridge.setSyncSummaryProvider { [weak self] in
            self?.currentSyncStoreState().summary
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

    var relayAccessStatusTitle: String? {
        guard configuration.backendMode == .relay,
              let account = relayAccountStatus?.account
        else {
            return nil
        }

        switch account.state {
        case .active:
            if account.creditBalance > 0 {
                return "在线可用"
            }
            return "额度用尽"
        case .paused:
            return "已暂停"
        case .expired:
            return "已过期"
        case .inactive:
            return "未激活"
        }
    }

    var relayAccessStatusMessage: String? {
        guard configuration.backendMode == .relay,
              let account = relayAccountStatus?.account
        else {
            return nil
        }

        var parts: [String] = []
        if let source = relayAccountStatus?.key?.source {
            parts.append(relaySourceLabel(for: source))
        }
        parts.append("\(account.creditBalance) credits")

        if let expiration = account.creditExpiresAt {
            parts.append("到期 \(expiration.formatted(date: .abbreviated, time: .shortened))")
        }

        if let note = account.adminNote?.nonEmptyTrimmed {
            parts.append(note)
        }

        return parts.joined(separator: " • ")
    }

    var hasManagedRelayAccess: Bool {
        guard configuration.backendMode == .relay else {
            return false
        }

        if configuration.relayBearerToken != nil {
            return true
        }

        guard let account = relayAccountStatus?.account,
              let key = relayAccountStatus?.key
        else {
            return false
        }

        return account.state == .active && key.state == .active && account.creditBalance > 0
    }

    var isReadOnlyMode: Bool {
        if hasManagedRelayAccess {
            return false
        }

        switch activationStatus {
        case .active:
            return false
        case .inactive, .pending, .expired, .exhausted, .invalid:
            return true
        }
    }

    var activationStatusTitle: String {
        if let relayAccessStatusTitle {
            return relayAccessStatusTitle
        }

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
        if let relayAccessStatusMessage {
            return relayAccessStatusMessage
        }

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
                state.license.creditLimit ?? 0
            )
        case .invalid(let message):
            return message
        }
    }

    var activationAllowedModelIDs: Set<String>? {
        if hasManagedRelayAccess {
            return nil
        }

        return OfflineActivation.allowedModelIDs(
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
            let loadedConversations = try await repository.loadConversations()
            let normalizedLoadedConversations = try await normalizeLoadedConversationsIfNeeded(loadedConversations)
            let loadedDeletedConversationTombstones = try await repository.loadDeletedConversationTombstones()
            let reconciledState = reconcileLoadedConversations(
                normalizedLoadedConversations,
                with: loadedDeletedConversationTombstones
            )
            setConversations(reconciledState.conversations)
            deletedConversationTombstones = reconciledState.tombstones
            if reconciledState.tombstonesChanged {
                try await repository.saveDeletedConversationTombstones(reconciledState.tombstones)
            }
            globalPinnedMemories = try await repository.loadGlobalPinnedMemories()
            promptPresets = PromptPreset.resolvedLibrary(from: try await repository.loadPromptPresets())
            await reconcileRemoteStores(requestBootstrap: false)
            syncBridge.requestBootstrapIfPossible()
            pushCurrentSyncSummary(force: true)
        } catch {
            startupError = error.localizedDescription
        }
    }

    func refreshRemoteSyncState() async {
        guard hasLoadedConversations else {
            await loadConversationsIfNeeded()
            return
        }

        await reconcileRemoteStores(requestBootstrap: true)
    }

    func refreshActivationState() async {
        activationState = activationRepository.loadState()
        relayAccountStatus = await relayAccessRepository.loadState()?.status
        rebuildConversationListCaches()

        guard configuration.backendMode == .relay else {
            return
        }

        do {
            let status = try await relayAccountService.refreshOrBootstrapStatus()
            await updateRelayAccountStatus(status, shareToCompanion: true)
        } catch {
            if relayAccountStatus == nil {
                startupError = error.localizedDescription
            }
        }
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
        try activationRepository.saveState(nextState)
        activationState = nextState
        rebuildConversationListCaches()

        if configuration.backendMode == .relay {
            let status = try await relayAccountService.exchangeOfflineActivation(
                code: rawCode,
                state: nextState
            )
            await updateRelayAccountStatus(status, shareToCompanion: true)
        }
    }

    func clearActivation() async {
        do {
            try activationRepository.clearState()
            activationState = nil
            rebuildConversationListCaches()
        } catch {
            startupError = error.localizedDescription
        }
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

    func refreshRelayCatalog() async {
        guard configuration.backendMode == .relay else {
            return
        }

        do {
            relayCatalog = try await relayAccountService.fetchCatalog()
        } catch {
            if relayCatalog == nil {
                startupError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func purchaseRelayPlan(id planID: String) async throws -> RelayStorePurchaseOutcome {
        guard configuration.backendMode == .relay else {
            throw RelayAPIError.missingConfiguration
        }

        relayBillingBusy = true
        defer { relayBillingBusy = false }

        if relayCatalog == nil {
            relayCatalog = try await relayAccountService.fetchCatalog()
        }

        guard let plan = relayCatalog?.plans.first(where: { $0.id == planID }) else {
            throw RelayAPIError.invalidResponse
        }

        #if canImport(StoreKit)
        let purchasePreparation = try await relayAccountService.preparePurchase()
        let products = try await Product.products(for: [plan.productID])
        guard let product = products.first(where: { $0.id == plan.productID }) else {
            throw RelayAPIError.invalidResponse
        }

        let result = try await product.purchase(
            options: Set([Product.PurchaseOption.appAccountToken(purchasePreparation.appAccountToken)])
        )

        switch result {
        case .success(let verificationResult):
            let transaction = try verifiedStoreTransaction(from: verificationResult)
            let status = try await relayAccountService.submitPurchase(
                transaction: submittedTransaction(
                    from: transaction,
                    signedTransactionInfo: verificationResult.jwsRepresentation
                )
            )
            await updateRelayAccountStatus(status, shareToCompanion: true)
            await transaction.finish()
            return .completed
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
        #else
        throw RelayAPIError.missingConfiguration
        #endif
    }

    @discardableResult
    func restoreRelayPurchases() async throws -> RelayAccountStatusResponse? {
        guard configuration.backendMode == .relay else {
            return nil
        }

        relayBillingBusy = true
        defer { relayBillingBusy = false }

        #if canImport(StoreKit)
        try await AppStore.sync()

        var submittedTransactions: [RelaySubmittedTransaction] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else {
                continue
            }
            submittedTransactions.append(
                submittedTransaction(
                    from: transaction,
                    signedTransactionInfo: entitlement.jwsRepresentation
                )
            )
        }

        let status = try await relayAccountService.restorePurchases(transactions: submittedTransactions)
        await updateRelayAccountStatus(status, shareToCompanion: true)
        return status
        #else
        throw RelayAPIError.missingConfiguration
        #endif
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
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.usesGlobalPinnedMemory = usesGlobalPinnedMemory
        }
    }

    func setUsesGlobalPinnedMemory(
        _ usesGlobalPinnedMemory: Bool,
        for conversationID: UUID
    ) {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        guard applyAIConfigurationMutationInMemory(for: conversationID, mutation: { configuration in
            configuration.usesGlobalPinnedMemory = usesGlobalPinnedMemory
        }) else {
            return
        }

        schedulePersistCurrentConversation(for: conversationID, sync: true)
    }

    func updateGoogleSearchEnabled(
        _ usesGoogleSearch: Bool,
        for conversationID: UUID
    ) async {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.usesGoogleSearch = usesGoogleSearch
        }
    }

    func setGoogleSearchEnabled(
        _ usesGoogleSearch: Bool,
        for conversationID: UUID
    ) {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        guard applyAIConfigurationMutationInMemory(for: conversationID, mutation: { configuration in
            configuration.usesGoogleSearch = usesGoogleSearch
        }) else {
            return
        }

        schedulePersistCurrentConversation(for: conversationID, sync: true)
    }

    func updateCodeExecutionEnabled(
        _ usesCodeExecution: Bool,
        for conversationID: UUID
    ) async {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        await updateAIConfiguration(for: conversationID) { configuration in
            configuration.usesCodeExecution = usesCodeExecution
        }
    }

    func setCodeExecutionEnabled(
        _ usesCodeExecution: Bool,
        for conversationID: UUID
    ) {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        guard applyAIConfigurationMutationInMemory(for: conversationID, mutation: { configuration in
            configuration.usesCodeExecution = usesCodeExecution
        }) else {
            return
        }

        schedulePersistCurrentConversation(for: conversationID, sync: true)
    }

    func setToolPreferences(
        usesGoogleSearch: Bool,
        usesCodeExecution: Bool,
        for conversationID: UUID
    ) {
        guard canUpdateAIConfiguration(for: conversationID) else {
            return
        }

        guard applyAIConfigurationMutationInMemory(for: conversationID, mutation: { configuration in
            configuration.usesGoogleSearch = usesGoogleSearch
            configuration.usesCodeExecution = usesCodeExecution
        }) else {
            return
        }

        schedulePersistCurrentConversation(for: conversationID, sync: true)
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
        if let index = conversationIndexByID[id],
           conversations.indices.contains(index),
           conversations[index].id == id {
            return conversations[index]
        }

        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        conversationIndexByID[id] = index
        return conversations[index]
    }

    func draftText(for conversationID: UUID) -> String {
        drafts[conversationID]?.text ?? ""
    }

    func latestReusableUserMessageText(for conversationID: UUID) -> String? {
        conversation(id: conversationID)?
            .messages
            .last(where: { $0.role == .user && $0.cleanedText.isEmpty == false })?
            .cleanedText
            .nonEmptyTrimmed
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

    @discardableResult
    func restoreLatestUserMessageToDraft(for conversationID: UUID) -> Bool {
        guard isReadOnlyMode == false,
              let previousMessageText = latestReusableUserMessageText(for: conversationID)
        else {
            return false
        }

        var draft = drafts[conversationID] ?? ConversationDraft()
        draft.text = previousMessageText
        drafts[conversationID] = draft
        return true
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
        await completionFeedbackProvider.prepareForPossibleBackgroundFeedback()

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
                await completionFeedbackProvider.notifyCompletion(of: .transcriptionCompleted)
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

    private func persist(
        _ conversation: ConversationThread,
        sync: Bool,
        allowResurrectionFromDeletedState: Bool = false
    ) async {
        guard shouldAllowConversationMutation(
            for: conversation,
            allowResurrectionFromDeletedState: allowResurrectionFromDeletedState
        ) else {
            return
        }

        do {
            let storedConversation = try await repository.save(conversation)
            mergeStoredAttachmentMetadata(from: storedConversation)
            if deletedConversationTombstones.removeValue(forKey: conversation.id) != nil {
                try await repository.saveDeletedConversationTombstones(deletedConversationTombstones)
            }
            await reconcileRemoteStores(requestBootstrap: false)
            if sync {
                syncBridge.pushConversation(storedConversation)
            }
            pushCurrentSyncSummary()
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func persistGlobalPinnedMemories(sync: Bool) async {
        do {
            try await repository.saveGlobalPinnedMemories(globalPinnedMemories)
            await reconcileRemoteStores(requestBootstrap: false)
            if sync {
                syncBridge.pushGlobalPinnedMemories(globalPinnedMemories)
            }
            pushCurrentSyncSummary()
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func persistPromptPresets(sync: Bool) async {
        do {
            try await repository.savePromptPresets(promptPresets)
            await reconcileRemoteStores(requestBootstrap: false)
            if sync {
                syncBridge.pushPromptPresets(promptPresets)
            }
            pushCurrentSyncSummary()
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func deleteConversation(id: UUID, deletedAt candidateDeletedAt: Date? = nil, sync: Bool) async {
        sendTasks[id]?.cancel()
        sendTasks[id] = nil
        setConversations(conversations.filter { $0.id != id })
        drafts[id] = nil
        conversationErrors[id] = nil
        sendingConversationIDs.remove(id)
        transcribingConversationIDs.remove(id)

        do {
            let deletedAt = max(deletedConversationTombstones[id] ?? .distantPast, candidateDeletedAt ?? .now)
            deletedConversationTombstones[id] = deletedAt
            try await repository.saveDeletedConversationTombstones(deletedConversationTombstones)
            try await repository.deleteConversation(id: id)
            await reconcileRemoteStores(requestBootstrap: false)
            if sync {
                syncBridge.pushDeletion(conversationID: id, deletedAt: deletedAt)
            }
            pushCurrentSyncSummary()
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func normalizeLoadedConversationsIfNeeded(
        _ conversations: [ConversationThread]
    ) async throws -> [ConversationThread] {
        var normalizedConversations: [ConversationThread] = []
        normalizedConversations.reserveCapacity(conversations.count)

        for conversation in conversations {
            let recoveredConversation = RecoveredStreamingMessageNormalizer
                .normalized(conversation: conversation)
                .conversation
            let normalizedConversation = normalizedConversationForStorage(recoveredConversation)
            normalizedConversations.append(normalizedConversation)

            if normalizedConversation != conversation {
                try await repository.save(normalizedConversation)
            }
        }

        return normalizedConversations
    }

    private func normalizedConversationForStorage(_ conversation: ConversationThread) -> ConversationThread {
        AssistantMessageContentNormalizer.normalized(conversation: conversation).conversation
    }

    private func upsertConversation(
        _ conversation: ConversationThread,
        allowResurrectionFromDeletedState: Bool = false
    ) {
        guard shouldAllowConversationMutation(
            for: conversation,
            allowResurrectionFromDeletedState: allowResurrectionFromDeletedState
        ) else {
            return
        }

        let existingConversationIndex = conversationIndexByID[conversation.id]
        let existingConversation = existingConversationIndex.map { conversations[$0] }
        var updatedConversations = conversations

        if let existingConversationIndex {
            updatedConversations.remove(at: existingConversationIndex)
        }

        let insertionIndex = conversationInsertionIndex(for: conversation, in: updatedConversations)
        updatedConversations.insert(conversation, at: insertionIndex)

        guard existingConversation != conversation || existingConversationIndex != insertionIndex else {
            return
        }

        conversations = updatedConversations
        rebuildConversationIndex()
        upsertConversationListItem(for: conversation, atConversationIndex: insertionIndex)
    }

    private func setConversations(_ updatedConversations: [ConversationThread]) {
        guard conversations != updatedConversations else {
            return
        }

        conversations = updatedConversations
        rebuildConversationIndex()
        rebuildConversationListCaches()
    }

    private func mergeStoredAttachmentMetadata(from storedConversation: ConversationThread) {
        guard var currentConversation = conversation(id: storedConversation.id) else {
            return
        }

        var changedAttachmentIDs: Set<UUID> = []
        let storedAttachmentsByID = Dictionary(
            uniqueKeysWithValues: storedConversation.messages
                .flatMap(\.attachments)
                .map { ($0.id, $0) }
        )

        for messageIndex in currentConversation.messages.indices {
            for attachmentIndex in currentConversation.messages[messageIndex].attachments.indices {
                let currentAttachment = currentConversation.messages[messageIndex].attachments[attachmentIndex]
                guard let storedAttachment = storedAttachmentsByID[currentAttachment.id],
                      currentAttachment.blobFilename != storedAttachment.blobFilename
                else {
                    continue
                }

                currentConversation.messages[messageIndex].attachments[attachmentIndex].blobFilename =
                    storedAttachment.blobFilename
                changedAttachmentIDs.insert(currentAttachment.id)
            }
        }

        guard changedAttachmentIDs.isEmpty == false else {
            return
        }

        upsertConversation(currentConversation)
    }

    private func rebuildConversationIndex() {
        conversationIndexByID = Dictionary(
            uniqueKeysWithValues: conversations.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    private func rebuildConversationListCaches() {
        let items = conversations.map(makeConversationListItem)
        applyConversationListItems(items)
    }

    private func conversationInsertionIndex(
        for conversation: ConversationThread,
        in sortedConversations: [ConversationThread]
    ) -> Int {
        sortedConversations.firstIndex { existingConversation in
            ConversationThread.sortsByMostRecentFirst(conversation, existingConversation)
        } ?? sortedConversations.endIndex
    }

    private func upsertConversationListItem(
        for conversation: ConversationThread,
        atConversationIndex conversationIndex: Int
    ) {
        let item = makeConversationListItem(for: conversation)

        if let existingItemIndex = conversationListItems.firstIndex(where: { $0.id == item.id }),
           existingItemIndex == conversationIndex,
           conversationListItems[existingItemIndex] == item {
            return
        }

        var updatedItems = conversationListItems
        if let existingItemIndex = updatedItems.firstIndex(where: { $0.id == item.id }) {
            updatedItems.remove(at: existingItemIndex)
        }

        updatedItems.insert(item, at: min(conversationIndex, updatedItems.count))
        applyConversationListItems(updatedItems)
    }

    private func applyConversationListItems(_ items: [WatchConversationListItem]) {
        if conversationListItems != items {
            conversationListItems = items
        }

        let favoriteItems = items.filter(\.isFavorite)
        if favoriteConversationListItems != favoriteItems {
            favoriteConversationListItems = favoriteItems
        }
    }

    private func makeConversationListItem(for conversation: ConversationThread) -> WatchConversationListItem {
        let summary = conversation.listSummary
        let effectiveConfiguration = licensedConfiguration(
            from: conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        )

        return WatchConversationListItem(
            id: conversation.id,
            title: conversation.title,
            updatedAt: conversation.updatedAt,
            isFavorite: conversation.isFavorite,
            previewText: summary.previewText,
            messageCount: summary.messageCount,
            containsAudioAttachments: summary.containsAudioAttachments,
            containsImageAttachments: summary.containsImageAttachments,
            modelShortLabel: AIModelCatalog.shortLabel(for: effectiveConfiguration.model),
            thinkingShortLabel: effectiveConfiguration.thinkingIntensity.shortLabel
        )
    }

    private func currentSyncStoreState() -> ConversationSyncStoreState {
        ConversationSyncStoreState(
            conversations: conversations,
            deletedConversationTombstones: deletedConversationTombstones,
            globalPinnedMemories: globalPinnedMemories,
            promptPresets: promptPresets
        )
    }

    private func applySyncStoreState(_ state: ConversationSyncStoreState) {
        let removedConversationIDs = Set(conversations.map(\.id))
            .subtracting(state.conversations.map(\.id))

        for conversationID in removedConversationIDs {
            sendTasks[conversationID]?.cancel()
            sendTasks[conversationID] = nil
            drafts[conversationID] = nil
            conversationErrors[conversationID] = nil
            sendingConversationIDs.remove(conversationID)
            transcribingConversationIDs.remove(conversationID)
        }

        setConversations(state.conversations)
        deletedConversationTombstones = state.deletedConversationTombstones
        globalPinnedMemories = state.globalPinnedMemories
        promptPresets = PromptPreset.resolvedLibrary(from: state.promptPresets)
    }

    private func reconcileRemoteStores(requestBootstrap: Bool) async {
        if let cloudSyncService {
            do {
                let mergedState = try await cloudSyncService.reconcile(localState: currentSyncStoreState())
                applySyncStoreState(mergedState)
            } catch {
                startupError = error.localizedDescription
            }
        }

        if requestBootstrap {
            requestBootstrapIfNeeded()
        }

        pushCurrentSyncSummary()
    }

    private func handleSyncStatusChange(_ status: CompanionSyncStatus) async {
        guard hasLoadedConversations else {
            return
        }

        switch status {
        case .reachable:
            await reconcileRemoteStores(requestBootstrap: true)
        case .idle:
            pushCurrentSyncSummary()
        case .unavailable, .notPaired, .companionMissing:
            return
        }
    }

    private func handleRemoteSyncSummary(_ summary: ConversationSyncSummary) {
        guard hasLoadedConversations else {
            return
        }

        let localSummary = currentSyncStoreState().summary
        guard localSummary != summary else {
            return
        }

        requestBootstrapIfNeeded()
    }

    private func requestBootstrapIfNeeded() {
        let now = Date.now
        if let lastBootstrapRequestAt,
           now.timeIntervalSince(lastBootstrapRequestAt) < 1
        {
            return
        }

        lastBootstrapRequestAt = now
        syncBridge.requestBootstrapIfPossible()
    }

    private func pushCurrentSyncSummary(force: Bool = false) {
        let summary = currentSyncStoreState().summary
        if force == false, lastPushedSyncSummaryDigest == summary.digest {
            return
        }

        lastPushedSyncSummaryDigest = summary.digest
        syncBridge.pushSyncSummary(summary)
    }

    private func shouldAllowConversationMutation(
        for conversation: ConversationThread,
        allowResurrectionFromDeletedState: Bool
    ) -> Bool {
        guard deletedConversationTombstones[conversation.id] != nil else {
            return true
        }

        if conversations.contains(where: { $0.id == conversation.id }) {
            return true
        }

        return false
    }

    func mergeRemoteConversation(_ conversation: ConversationThread) async {
        guard shouldAcceptRemoteConversation(conversation) else {
            return
        }

        let normalizedConversation = normalizedConversationForStorage(conversation)
        let hydratedConversation = await repository.hydrateAttachments(in: normalizedConversation)
        upsertConversation(
            hydratedConversation,
            allowResurrectionFromDeletedState: true
        )
        await persist(
            hydratedConversation,
            sync: false,
            allowResurrectionFromDeletedState: true
        )
    }

    func mergeRemoteConversationSnapshot(_ remoteConversations: [ConversationThread]) async {
        for remoteConversation in remoteConversations {
            guard shouldAcceptRemoteConversation(remoteConversation) else {
                continue
            }

            if let localConversation = conversation(id: remoteConversation.id),
               localConversation.updatedAt > remoteConversation.updatedAt {
                syncBridge.pushConversation(localConversation)
                continue
            }

            let normalizedConversation = normalizedConversationForStorage(remoteConversation)
            let hydratedConversation = await repository.hydrateAttachments(in: normalizedConversation)
            upsertConversation(
                hydratedConversation,
                allowResurrectionFromDeletedState: true
            )
            await persist(
                hydratedConversation,
                sync: false,
                allowResurrectionFromDeletedState: true
            )
        }
    }

    func mergeRemoteDeletedConversationTombstones(
        _ incomingTombstones: [CompanionDeletedConversationTombstone]
    ) async {
        for tombstone in mergedDeletedConversationTombstones(incomingTombstones) {
            await deleteConversation(id: tombstone.id, deletedAt: tombstone.deletedAt, sync: false)
        }
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
        modelResponseParts: [GeminiPartPayload]?,
        attachments: [ChatAttachment],
        status: ChatMessageStatus,
        fallbackCreatedAt: Date
    ) {
        let normalizedMessage = AssistantMessageContentNormalizer.normalized(
            message: ChatMessage(
                id: id,
                role: .assistant,
                text: text,
                thoughtSummary: thoughtSummary.nonEmptyTrimmed,
                modelResponseParts: modelResponseParts,
                createdAt: fallbackCreatedAt,
                attachments: attachments,
                status: status
            )
        )

        mutateConversation(id: conversationID) { conversation in
            conversation.upsertMessage(
                ChatMessage(
                    id: normalizedMessage.id,
                    role: normalizedMessage.role,
                    text: normalizedMessage.text,
                    thoughtSummary: normalizedMessage.thoughtSummary,
                    modelResponseParts: normalizedMessage.modelResponseParts,
                    createdAt: conversation.messages.first(where: { $0.id == id })?.createdAt ?? fallbackCreatedAt,
                    attachments: normalizedMessage.attachments,
                    status: normalizedMessage.status
                ),
                updatesTimestamp: status != .streaming
            )
        }
    }

    private func updateAIConfiguration(
        for conversationID: UUID,
        mutation: (inout ConversationAIConfiguration) -> Void
    ) async {
        guard applyAIConfigurationMutationInMemory(for: conversationID, mutation: mutation) else {
            return
        }

        await persistCurrentConversation(for: conversationID, sync: true)
    }

    private func canUpdateAIConfiguration(for conversationID: UUID) -> Bool {
        if let activationMessage = activationFailureMessage(for: aiConfiguration(for: conversationID).model) {
            conversationErrors[conversationID] = activationMessage
            return false
        }

        return true
    }

    @discardableResult
    private func applyAIConfigurationMutationInMemory(
        for conversationID: UUID,
        mutation: (inout ConversationAIConfiguration) -> Void
    ) -> Bool {
        guard var conversation = conversation(id: conversationID) else {
            return false
        }

        var resolvedConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        mutation(&resolvedConfiguration)
        resolvedConfiguration = licensedConfiguration(from: resolvedConfiguration)
        conversation.updateAIConfiguration(resolvedConfiguration)
        upsertConversation(conversation)
        return true
    }

    private func schedulePersistCurrentConversation(
        for conversationID: UUID,
        sync: Bool
    ) {
        Task { [weak self] in
            await self?.persistCurrentConversation(for: conversationID, sync: sync)
        }
    }

    private func persistCurrentConversation(
        for conversationID: UUID,
        sync: Bool
    ) async {
        guard let conversation = conversation(id: conversationID) else {
            return
        }

        await persist(conversation, sync: sync)
    }

    private func licensedConfiguration(from configuration: ConversationAIConfiguration) -> ConversationAIConfiguration {
        if hasManagedRelayAccess {
            return configuration
        }

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
        if configuration.backendMode == .relay {
            if hasManagedRelayAccess {
                return nil
            }

            if let account = relayAccountStatus?.account {
                switch account.state {
                case .active:
                    return account.creditBalance > 0 ? nil : "在线额度已用尽。"
                case .paused:
                    return "当前 relay key 已在服务端暂停。"
                case .expired:
                    return "订阅或 credit 已过期。"
                case .inactive:
                    return "当前设备尚未完成在线激活。"
                }
            }
        }

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
        guard hasManagedRelayAccess == false else {
            return
        }

        let nextActivationState = try OfflineActivation.consumeMessage(
            from: activationState,
            deviceToken: deviceIdentity.deviceToken,
            modelID: modelID
        )

        if nextActivationState != activationState {
            try activationRepository.saveState(nextActivationState)
            activationState = nextActivationState
            rebuildConversationListCaches()
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
        let replyPersistenceToken = replyPersistenceController.beginStreamingReplyPersistence()

        defer {
            replyPersistenceController.endStreamingReplyPersistence(replyPersistenceToken)
        }

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
            modelResponseParts: nil,
            attachments: [],
            status: .streaming,
            fallbackCreatedAt: assistantMessageCreatedAt
        )
        await completionFeedbackProvider.prepareForPossibleBackgroundFeedback()

        let maximumRetryCount = sendFailureRetryLimit
        var finalError: Error?
        var finalStreamedText = ""
        var finalStreamedThoughtSummary = ""
        var finalStreamedModelResponseParts: [GeminiPartPayload]?
        var finalStreamedAttachments: [ChatAttachment] = []
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
                        modelResponseParts: nil,
                        attachments: [],
                        status: .streaming,
                        fallbackCreatedAt: assistantMessageCreatedAt
                    )

                    let delay = sendRetryDelayNanoseconds(attempt)
                    if delay > 0 {
                        try await Task.sleep(nanoseconds: delay)
                    }
                }

                try Task.checkCancellation()

                let streamedSnapshot = try await collectAssistantReplyStream(
                    from: aiService.streamReply(for: requestConversation),
                    flushInterval: 0.05,
                    persistenceInterval: Self.streamingProgressPersistenceInterval
                ) { snapshot, shouldPersist in
                    self.upsertAssistantMessage(
                        id: assistantMessageID,
                        in: conversationID,
                        text: snapshot.text,
                        thoughtSummary: snapshot.thoughtSummary,
                        modelResponseParts: snapshot.modelResponseParts,
                        attachments: snapshot.attachments,
                        status: .streaming,
                        fallbackCreatedAt: assistantMessageCreatedAt
                    )

                    if shouldPersist,
                       let streamingConversation = self.conversation(id: conversationID) {
                        await self.persist(streamingConversation, sync: false)
                    }
                }

                try Task.checkCancellation()

                upsertAssistantMessage(
                    id: assistantMessageID,
                    in: conversationID,
                    text: streamedSnapshot.text,
                    thoughtSummary: streamedSnapshot.thoughtSummary,
                    modelResponseParts: streamedSnapshot.modelResponseParts,
                    attachments: streamedSnapshot.attachments,
                    status: .sent,
                    fallbackCreatedAt: assistantMessageCreatedAt
                )

                if let finalizedConversation = conversation(id: conversationID) {
                    await persist(finalizedConversation, sync: true)
                    await refreshConversationArtifacts(for: conversationID)

                    if finalizedConversation.messages.contains(where: {
                        $0.id == assistantMessageID && $0.hasVisibleContent && $0.status == .sent
                    }) {
                        await completionFeedbackProvider.notifyCompletion(of: .assistantReplyCompleted)
                    }
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
                finalStreamedModelResponseParts = conversation(id: conversationID)?
                    .messages
                    .first(where: { $0.id == assistantMessageID })?
                    .modelResponseParts
                finalStreamedAttachments = conversation(id: conversationID)?
                    .messages
                    .first(where: { $0.id == assistantMessageID })?
                    .attachments ?? []

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
            if finalStreamedText.isEmpty,
               finalStreamedThoughtSummary.isEmpty,
               finalStreamedModelResponseParts?.isEmpty != false,
               finalStreamedAttachments.isEmpty {
                conversation.removeMessage(id: assistantMessageID)
            } else {
                conversation.upsertMessage(
                    ChatMessage(
                        id: assistantMessageID,
                        role: .assistant,
                        text: finalStreamedText,
                        thoughtSummary: finalStreamedThoughtSummary.nonEmptyTrimmed,
                        modelResponseParts: finalStreamedModelResponseParts,
                        createdAt: conversation.messages.first(where: { $0.id == assistantMessageID })?.createdAt ?? assistantMessageCreatedAt,
                        attachments: finalStreamedAttachments,
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

    #if canImport(StoreKit)
    private func verifiedStoreTransaction(
        from verificationResult: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch verificationResult {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }

    private func submittedTransaction(
        from transaction: Transaction,
        signedTransactionInfo: String?
    ) -> RelaySubmittedTransaction {
        RelaySubmittedTransaction(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            environment: nil,
            signedTransactionInfo: signedTransactionInfo,
            signedRenewalInfo: nil,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revokedDate: transaction.revocationDate
        )
    }
    #endif

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

    private func relaySourceLabel(for source: RelayAccessSource) -> String {
        switch source {
        case .trial:
            return "试用"
        case .subscription:
            return "订阅"
        case .offlineManual:
            return "离线导入"
        }
    }

    private func handleSyncEvent(_ event: CompanionSyncEvent) async {
        switch event {
        case .upsert(let conversation):
            await mergeRemoteConversation(conversation)
        case .delete(let conversationID, let deletedAt):
            await mergeRemoteDeletedConversationTombstones([
                CompanionDeletedConversationTombstone(id: conversationID, deletedAt: deletedAt)
            ])
        case .deletedConversationTombstones(let tombstones):
            await mergeRemoteDeletedConversationTombstones(tombstones)
        case .snapshot(let conversations):
            await mergeRemoteConversationSnapshot(conversations)
        case .syncSummary(let summary):
            handleRemoteSyncSummary(summary)
        case .attachmentBlob(let incomingBlob):
            await mergeIncomingAttachmentBlob(incomingBlob)
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
        case .relayPairingToken(let token, let expiresAt):
            await consumeRelayPairingToken(token, expiresAt: expiresAt)
        }
    }

    private func updateRelayAccountStatus(
        _ status: RelayAccountStatusResponse?,
        shareToCompanion: Bool
    ) async {
        let previousStatus = relayAccountStatus
        relayAccountStatus = status
        rebuildConversationListCaches()

        guard shareToCompanion else {
            return
        }

        let previouslyActive = isManagedRelayAccessActive(for: previousStatus)
        let nowActive = isManagedRelayAccessActive(for: status)
        let keyChanged = previousStatus?.key?.keyValue != status?.key?.keyValue

        guard nowActive, previouslyActive == false || keyChanged else {
            return
        }

        await shareManagedRelayAccessToCompanionIfPossible()
    }

    private func isManagedRelayAccessActive(for status: RelayAccountStatusResponse?) -> Bool {
        guard configuration.backendMode == .relay else {
            return false
        }

        if configuration.relayBearerToken != nil {
            return true
        }

        guard let account = status?.account,
              let key = status?.key
        else {
            return false
        }

        return account.state == .active && key.state == .active && account.creditBalance > 0
    }

    private func shareManagedRelayAccessToCompanionIfPossible() async {
        guard configuration.backendMode == .relay,
              configuration.relayBearerToken == nil,
              canTransferActivationCodeToPairedWatch,
              isManagedRelayAccessActive(for: relayAccountStatus)
        else {
            return
        }

        do {
            let pairingToken = try await relayAccountService.requestPairingToken()
            syncBridge.pushRelayPairingToken(pairingToken.pairingToken, expiresAt: pairingToken.expiresAt)
        } catch {
            companionActivationFeedbackMessage = "在线激活同步失败：\(error.localizedDescription)"
        }
    }

    private func consumeRelayPairingToken(_ token: String, expiresAt: Date?) async {
        guard configuration.backendMode == .relay else {
            return
        }

        if let expiresAt, expiresAt <= .now {
            return
        }

        do {
            let status = try await relayAccountService.joinPaired(pairingToken: token)
            await updateRelayAccountStatus(status, shareToCompanion: false)
            companionActivationFeedbackMessage = "已同步配对设备的在线激活。"
        } catch {
            companionActivationFeedbackMessage = "同步在线激活失败：\(error.localizedDescription)"
        }
    }

    private func mergeIncomingAttachmentBlob(_ incomingBlob: CompanionIncomingAttachmentBlob) async {
        let blobData: Data

        do {
            blobData = try await repository.importAttachmentBlob(
                from: incomingBlob.temporaryFileURL,
                as: incomingBlob.blobFilename
            )
        } catch {
            startupError = error.localizedDescription
            return
        }

        guard var conversation = conversation(id: incomingBlob.conversationID) else {
            return
        }

        var didChange = false

        for messageIndex in conversation.messages.indices {
            guard conversation.messages[messageIndex].id == incomingBlob.messageID else {
                continue
            }

            for attachmentIndex in conversation.messages[messageIndex].attachments.indices {
                guard conversation.messages[messageIndex].attachments[attachmentIndex].id == incomingBlob.attachmentID else {
                    continue
                }

                conversation.messages[messageIndex].attachments[attachmentIndex].blobFilename = incomingBlob.blobFilename
                conversation.messages[messageIndex].attachments[attachmentIndex].data = blobData
                didChange = true
            }
        }

        guard didChange else {
            return
        }

        upsertConversation(
            conversation,
            allowResurrectionFromDeletedState: true
        )
        await persist(
            conversation,
            sync: false,
            allowResurrectionFromDeletedState: true
        )
    }

    private func shouldAcceptRemoteConversation(_ conversation: ConversationThread) -> Bool {
        deletedConversationTombstones[conversation.id] == nil
    }

    private func mergedDeletedConversationTombstones(
        _ incomingTombstones: [CompanionDeletedConversationTombstone]
    ) -> [CompanionDeletedConversationTombstone] {
        var latestTombstoneByID: [UUID: Date] = [:]

        for tombstone in incomingTombstones {
            let latestDeletedAt = max(
                max(
                    deletedConversationTombstones[tombstone.id] ?? .distantPast,
                    latestTombstoneByID[tombstone.id] ?? .distantPast
                ),
                tombstone.deletedAt
            )
            latestTombstoneByID[tombstone.id] = latestDeletedAt
        }

        return latestTombstoneByID.map {
            CompanionDeletedConversationTombstone(id: $0.key, deletedAt: $0.value)
        }
        .sorted { lhs, rhs in
            if lhs.deletedAt == rhs.deletedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.deletedAt > rhs.deletedAt
        }
    }

    private func reconcileLoadedConversations(
        _ loadedConversations: [ConversationThread],
        with tombstones: [UUID: Date]
    ) -> (conversations: [ConversationThread], tombstones: [UUID: Date], tombstonesChanged: Bool) {
        var visibleConversations: [ConversationThread] = []

        for conversation in loadedConversations {
            if tombstones[conversation.id] != nil {
                continue
            }

            visibleConversations.append(conversation)
        }

        return (
            visibleConversations.sorted(by: ConversationThread.sortsByMostRecentFirst),
            tombstones,
            false
        )
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
private nonisolated struct PreviewAIStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.thoughtDelta("Reviewing the draft and condensing the most useful points."))
            continuation.yield(.answerDelta("This is a preview reply from the mock AI service."))
            continuation.finish()
        }
    }
}

private nonisolated struct PreviewAITranscriptionService: AITranscriptionService {
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
        activationState: OfflineActivationState? = OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: 0,
                requestIssuedAt: .now,
                validFrom: .now,
                validUntil: nil,
                messageLimit: nil,
                modelMask: LicensedModelCatalog.unrestrictedMask
            ),
            activationCodeFingerprint: "preview",
            activatedAt: .now,
            usedMessageCount: 0
        ),
        aiService: AIStreamingService = PreviewAIStreamingService(),
        transcriptionService: AITranscriptionService? = PreviewAITranscriptionService(),
        completionFeedbackProvider: (any CompletionFeedbackProviding)? = nil,
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
            aiService: aiService,
            transcriptionService: transcriptionService,
            completionFeedbackProvider: completionFeedbackProvider,
            configuration: configuration,
            syncBridge: CompanionSyncBridge(isEnabled: false),
            replyPersistenceController: NoopReplyPersistenceController()
        )

        store.setConversations(conversations.sorted(by: ConversationThread.sortsByMostRecentFirst))
        store.drafts = drafts
        store.sendingConversationIDs = sendingConversationIDs
        store.transcribingConversationIDs = []
        store.conversationErrors = conversationErrors
        store.startupError = startupError
        store.activationState = activationState.map { previewState in
            OfflineActivationState(
                license: OfflineActivationLicense(
                    deviceToken: store.deviceIdentity.deviceToken,
                    requestIssuedAt: previewState.license.requestIssuedAt,
                    validFrom: previewState.license.validFrom,
                    validUntil: previewState.license.validUntil,
                    messageLimit: previewState.license.messageLimit,
                    modelMask: previewState.license.modelMask
                ),
                activationCodeFingerprint: previewState.activationCodeFingerprint,
                activatedAt: previewState.activatedAt,
                usedMessageCount: previewState.usedMessageCount
            )
        }
        store.rebuildConversationListCaches()
        store.hasLoadedConversations = true
        return store
    }
}
#endif
