//
//  ConversationSyncCoordinator.swift
//  AIChat Watch App
//
//  Extracted from ChatStore — cross-device sync orchestration via
//  CompanionSyncBridge and ICloudConversationSyncService.
//

import Combine
import Foundation

@MainActor
final class ConversationSyncCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var syncStatus: CompanionSyncStatus
    @Published private(set) var syncStatusDescription: String
    @Published private(set) var deletedConversationTombstones: [UUID: Date] = [:]

    // MARK: - Dependencies

    private let syncBridge: CompanionSyncBridge
    private let cloudSyncService: ICloudConversationSyncService?
    private let repository: ConversationRepository
    private let activationBilling: ActivationBillingService

    // MARK: - Callbacks into ChatStore

    /// Upsert a conversation into the store.
    var onUpsertConversation: ((ConversationThread, _ allowResurrection: Bool) -> Void)?

    /// Persist a conversation to disk.
    var onPersistConversation: ((ConversationThread, _ sync: Bool, _ allowResurrection: Bool) async -> Void)?

    /// Delete a conversation by ID.
    var onDeleteConversation: ((UUID, Date?, _ sync: Bool) async -> Void)?

    /// Replace the full conversation + state arrays (from CloudKit merge).
    var onApplySyncStoreState: ((ConversationSyncStoreState) -> Void)?

    /// Read-only access to ChatStore's current conversations.
    var conversationsProvider: (() -> [ConversationThread])?

    /// Read-only access to a single conversation by ID.
    var conversationProvider: ((UUID) -> ConversationThread?)?

    /// Read-only access to global pinned memories.
    var globalPinnedMemoriesProvider: (() -> [PinnedMemoryItem])?

    /// Write global pinned memories.
    var onSetGlobalPinnedMemories: (([PinnedMemoryItem]) -> Void)?

    /// Persist global pinned memories.
    var onPersistGlobalPinnedMemories: ((_ sync: Bool) async -> Void)?

    /// Read-only access to prompt presets.
    var promptPresetsProvider: (() -> [PromptPreset])?

    /// Write prompt presets.
    var onSetPromptPresets: (([PromptPreset]) -> Void)?

    /// Persist prompt presets.
    var onPersistPromptPresets: ((_ sync: Bool) async -> Void)?

    /// Report a startup error.
    var onStartupError: ((String) -> Void)?

    /// Whether conversations have been loaded.
    var hasLoadedConversationsProvider: (() -> Bool)?

    // MARK: - Private State

    private var lastPushedSyncSummaryDigest: String?
    private var lastBootstrapRequestAt: Date?
    /// Throttle for the full reconcile triggered on each `.reachable`
    /// transition. WatchConnectivity reachability flaps frequently
    /// (Bluetooth proximity, wrist-up). Without this gate every flap
    /// kicks off a full iCloud reconcile, which is expensive (M9 in
    /// the watch-services review).
    private var lastReachableReconcileAt: Date?
    private let reachableReconcileMinInterval: TimeInterval = 30

    // MARK: - Init

    init(
        syncBridge: CompanionSyncBridge,
        cloudSyncService: ICloudConversationSyncService?,
        repository: ConversationRepository,
        activationBilling: ActivationBillingService
    ) {
        self.syncBridge = syncBridge
        self.cloudSyncService = cloudSyncService
        self.repository = repository
        self.activationBilling = activationBilling
        self.syncStatus = syncBridge.currentStatus
        self.syncStatusDescription = syncBridge.currentStatus.description
    }

    // MARK: - Sync Bridge Wiring

    func wireSyncBridge() {
        syncBridge.setStatusHandler { [weak self] status in
            guard let self else { return }
            self.syncStatus = status
            self.syncStatusDescription = status.description
            Task { @MainActor [weak self] in
                await self?.handleSyncStatusChange(status)
            }
        }

        syncBridge.setSnapshotProvider { [weak self] in
            self?.conversationsProvider?() ?? []
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
            self?.globalPinnedMemoriesProvider?() ?? []
        }

        syncBridge.setPromptPresetsProvider { [weak self] in
            self?.promptPresetsProvider?() ?? PromptPreset.builtInPresets
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

    // MARK: - Public API

    func reconcileRemoteStores(requestBootstrap: Bool) async {
        if let cloudSyncService {
            do {
                let mergedState = try await cloudSyncService.reconcile(localState: currentSyncStoreState())
                onApplySyncStoreState?(mergedState)
                deletedConversationTombstones = mergedState.deletedConversationTombstones
            } catch {
                onStartupError?(error.localizedDescription)
            }
        }

        if requestBootstrap {
            requestBootstrapIfNeeded()
        }

        pushCurrentSyncSummary()
    }

    func pushCurrentSyncSummary(force: Bool = false) {
        let summary = currentSyncStoreState().summary
        if force == false, lastPushedSyncSummaryDigest == summary.digest {
            return
        }

        lastPushedSyncSummaryDigest = summary.digest
        syncBridge.pushSyncSummary(summary)
    }

    func requestBootstrapIfPossible() {
        syncBridge.requestBootstrapIfPossible()
    }

    func pushConversation(_ conversation: ConversationThread) {
        syncBridge.pushConversation(conversation)
    }

    func pushDeletion(conversationID: UUID, deletedAt: Date) {
        syncBridge.pushDeletion(conversationID: conversationID, deletedAt: deletedAt)
    }

    func pushGlobalPinnedMemories(_ items: [PinnedMemoryItem]) {
        syncBridge.pushGlobalPinnedMemories(items)
    }

    func pushPromptPresets(_ presets: [PromptPreset]) {
        syncBridge.pushPromptPresets(presets)
    }

    // MARK: - Tombstone Management

    func shouldAcceptRemoteConversation(_ conversation: ConversationThread) -> Bool {
        deletedConversationTombstones[conversation.id] == nil
    }

    func shouldAllowConversationMutation(
        for conversation: ConversationThread,
        allowResurrectionFromDeletedState: Bool
    ) -> Bool {
        guard deletedConversationTombstones[conversation.id] != nil else {
            return true
        }

        if let conversations = conversationsProvider?(),
           conversations.contains(where: { $0.id == conversation.id }) {
            return true
        }

        return false
    }

    func recordDeletion(id: UUID, deletedAt: Date) {
        let latest = max(deletedConversationTombstones[id] ?? .distantPast, deletedAt)
        deletedConversationTombstones[id] = latest
    }

    func removeTombstone(for conversationID: UUID) -> Bool {
        deletedConversationTombstones.removeValue(forKey: conversationID) != nil
    }

    func reconcileLoadedConversations(
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

        deletedConversationTombstones = tombstones

        return (
            visibleConversations.sorted(by: ConversationThread.sortsByMostRecentFirst),
            tombstones,
            false
        )
    }

    func saveTombstones() async throws {
        try await repository.saveDeletedConversationTombstones(deletedConversationTombstones)
    }

    // MARK: - Sync Event Handling

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
        case .activationRequestCode, .activationCodeImport, .relayPairingToken:
            await activationBilling.handleActivationSyncEvent(event)
        }
    }

    // MARK: - Merge Logic

    private func mergeRemoteConversation(_ conversation: ConversationThread) async {
        guard shouldAcceptRemoteConversation(conversation) else {
            return
        }

        let normalizedConversation = AssistantMessageContentNormalizer.normalized(conversation: conversation).conversation
        let hydratedConversation = await repository.hydrateAttachments(in: normalizedConversation)
        onUpsertConversation?(hydratedConversation, true)
        await onPersistConversation?(hydratedConversation, false, true)
    }

    func mergeRemoteConversationSnapshot(_ remoteConversations: [ConversationThread]) async {
        for remoteConversation in remoteConversations {
            guard shouldAcceptRemoteConversation(remoteConversation) else {
                continue
            }

            if let localConversation = conversationProvider?(remoteConversation.id),
               localConversation.updatedAt > remoteConversation.updatedAt {
                syncBridge.pushConversation(localConversation)
                continue
            }

            let normalizedConversation = AssistantMessageContentNormalizer.normalized(conversation: remoteConversation).conversation
            let hydratedConversation = await repository.hydrateAttachments(in: normalizedConversation)
            onUpsertConversation?(hydratedConversation, true)
            await onPersistConversation?(hydratedConversation, false, true)
        }
    }

    func mergeRemoteDeletedConversationTombstones(
        _ incomingTombstones: [CompanionDeletedConversationTombstone]
    ) async {
        for tombstone in mergedDeletedConversationTombstones(incomingTombstones) {
            await onDeleteConversation?(tombstone.id, tombstone.deletedAt, false)
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
            onStartupError?(error.localizedDescription)
            return
        }

        guard var conversation = conversationProvider?(incomingBlob.conversationID) else {
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

        onUpsertConversation?(conversation, true)
        await onPersistConversation?(conversation, false, true)
    }

    private func mergeGlobalPinnedMemories(
        _ incomingItems: [PinnedMemoryItem],
        syncMergedState: Bool
    ) async {
        guard let currentMemories = globalPinnedMemoriesProvider?() else {
            return
        }

        var itemsByID = Dictionary(uniqueKeysWithValues: currentMemories.map { ($0.id, $0) })

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

        guard mergedItems != currentMemories else {
            return
        }

        onSetGlobalPinnedMemories?(mergedItems)
        await onPersistGlobalPinnedMemories?(syncMergedState)
    }

    private func replacePromptPresets(
        _ incomingPresets: [PromptPreset],
        syncMergedState: Bool
    ) async {
        let resolvedPresets = PromptPreset.resolvedLibrary(from: incomingPresets)
        guard let currentPresets = promptPresetsProvider?(),
              resolvedPresets != currentPresets else {
            return
        }

        onSetPromptPresets?(resolvedPresets)
        await onPersistPromptPresets?(syncMergedState)
    }

    // MARK: - Private Helpers

    private func currentSyncStoreState() -> ConversationSyncStoreState {
        ConversationSyncStoreState(
            conversations: conversationsProvider?() ?? [],
            deletedConversationTombstones: deletedConversationTombstones,
            globalPinnedMemories: globalPinnedMemoriesProvider?() ?? [],
            promptPresets: promptPresetsProvider?() ?? PromptPreset.builtInPresets
        )
    }

    private func handleSyncStatusChange(_ status: CompanionSyncStatus) async {
        guard hasLoadedConversationsProvider?() == true else {
            return
        }

        switch status {
        case .reachable:
            // Reachability flaps are common on watch — gate the full
            // reconcile to at most one per `reachableReconcileMinInterval`
            // seconds. The first reachable transition still always
            // reconciles because `lastReachableReconcileAt` starts nil.
            let now = Date.now
            if let lastReachableReconcileAt,
               now.timeIntervalSince(lastReachableReconcileAt) < reachableReconcileMinInterval {
                // Still ask the bootstrap throttle — that path is
                // cheap and handles its own dedupe.
                requestBootstrapIfNeeded()
                return
            }
            lastReachableReconcileAt = now
            await reconcileRemoteStores(requestBootstrap: true)
        case .idle:
            pushCurrentSyncSummary()
        case .unavailable, .notPaired, .companionMissing:
            return
        }
    }

    private func handleRemoteSyncSummary(_ summary: ConversationSyncSummary) {
        guard hasLoadedConversationsProvider?() == true else {
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
           now.timeIntervalSince(lastBootstrapRequestAt) < 1 {
            return
        }

        lastBootstrapRequestAt = now
        syncBridge.requestBootstrapIfPossible()
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
}
