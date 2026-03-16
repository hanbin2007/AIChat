//
//  ICloudConversationSyncService.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/15.
//

import CryptoKit
import Foundation

nonisolated struct ConversationSyncSummary: Codable, Equatable, Hashable {
    let conversationCount: Int
    let messageCount: Int
    let attachmentCount: Int
    let deletedConversationCount: Int
    let globalPinnedMemoryCount: Int
    let promptPresetCount: Int
    let latestConversationUpdatedAt: Date?
    let latestDeletedConversationAt: Date?
    let digest: String
}

nonisolated struct ConversationSyncStoreState: Equatable {
    var conversations: [ConversationThread]
    var deletedConversationTombstones: [UUID: Date]
    var globalPinnedMemories: [PinnedMemoryItem]
    var promptPresets: [PromptPreset]

    init(
        conversations: [ConversationThread] = [],
        deletedConversationTombstones: [UUID: Date] = [:],
        globalPinnedMemories: [PinnedMemoryItem] = [],
        promptPresets: [PromptPreset] = PromptPreset.builtInPresets
    ) {
        self.conversations = conversations.sorted(by: ConversationThread.sortsByMostRecentFirst)
        self.deletedConversationTombstones = deletedConversationTombstones
        self.globalPinnedMemories = Self.sortedPinnedMemories(globalPinnedMemories)
        self.promptPresets = PromptPreset.resolvedLibrary(from: promptPresets)
    }

    var summary: ConversationSyncSummary {
        let attachmentCount = conversations.reduce(into: 0) { total, conversation in
            total += conversation.messages.reduce(into: 0) { messageTotal, message in
                messageTotal += message.attachments.count
            }
        }
        let messageCount = conversations.reduce(into: 0) { total, conversation in
            total += conversation.messages.count
        }

        return ConversationSyncSummary(
            conversationCount: conversations.count,
            messageCount: messageCount,
            attachmentCount: attachmentCount,
            deletedConversationCount: deletedConversationTombstones.count,
            globalPinnedMemoryCount: globalPinnedMemories.count,
            promptPresetCount: promptPresets.count,
            latestConversationUpdatedAt: conversations.map(\.updatedAt).max(),
            latestDeletedConversationAt: deletedConversationTombstones.values.max(),
            digest: digest
        )
    }

    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let payload = DigestPayload(
            conversations: conversations.map(\.digestSanitizedCopy),
            deletedConversationTombstones: deletedConversationTombstones
                .map { DeletedConversationDigestEntry(id: $0.key, deletedAt: $0.value) }
                .sorted(by: DeletedConversationDigestEntry.sortsByMostRecentFirst),
            globalPinnedMemories: Self.sortedPinnedMemories(globalPinnedMemories),
            promptPresets: PromptPreset.resolvedLibrary(from: promptPresets)
        )

        guard let data = try? encoder.encode(payload) else {
            return ""
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func merged(
        local localState: ConversationSyncStoreState,
        remote remoteState: ConversationSyncStoreState
    ) -> ConversationSyncStoreState {
        var mergedTombstones = mergeDeletedConversationTombstones(
            localState.deletedConversationTombstones,
            remoteState.deletedConversationTombstones
        )

        var latestConversationByID: [UUID: ConversationThread] = [:]

        for conversation in localState.conversations + remoteState.conversations {
            guard let existing = latestConversationByID[conversation.id] else {
                latestConversationByID[conversation.id] = conversation
                continue
            }

            if shouldPreferConversation(conversation, over: existing) {
                latestConversationByID[conversation.id] = conversation
            }
        }

        let survivingConversations = latestConversationByID.values.compactMap { conversation -> ConversationThread? in
            guard let deletedAt = mergedTombstones[conversation.id] else {
                return conversation
            }

            guard conversation.updatedAt > deletedAt else {
                return nil
            }

            mergedTombstones.removeValue(forKey: conversation.id)
            return conversation
        }
        .sorted(by: ConversationThread.sortsByMostRecentFirst)

        return ConversationSyncStoreState(
            conversations: survivingConversations,
            deletedConversationTombstones: mergedTombstones,
            globalPinnedMemories: mergePinnedMemories(
                localState.globalPinnedMemories,
                remoteState.globalPinnedMemories
            ),
            promptPresets: mergePromptPresets(
                localState.promptPresets,
                remoteState.promptPresets
            )
        )
    }

    private static func shouldPreferConversation(
        _ candidate: ConversationThread,
        over existing: ConversationThread
    ) -> Bool {
        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }

        let candidateScore = candidate.syncRichnessScore
        let existingScore = existing.syncRichnessScore
        if candidateScore != existingScore {
            return existingScore.lexicographicallyPrecedes(candidateScore)
        }

        let candidateDigest = candidate.syncDigestSeed
        let existingDigest = existing.syncDigestSeed
        return candidateDigest > existingDigest
    }

    private static func mergeDeletedConversationTombstones(
        _ lhs: [UUID: Date],
        _ rhs: [UUID: Date]
    ) -> [UUID: Date] {
        var merged = lhs

        for (conversationID, deletedAt) in rhs {
            merged[conversationID] = max(merged[conversationID] ?? .distantPast, deletedAt)
        }

        return merged
    }

    private static func mergePinnedMemories(
        _ lhs: [PinnedMemoryItem],
        _ rhs: [PinnedMemoryItem]
    ) -> [PinnedMemoryItem] {
        var itemsByID = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })

        for item in rhs {
            if let existing = itemsByID[item.id], existing.updatedAt >= item.updatedAt {
                continue
            }

            itemsByID[item.id] = item
        }

        return sortedPinnedMemories(Array(itemsByID.values))
    }

    private static func mergePromptPresets(
        _ lhs: [PromptPreset],
        _ rhs: [PromptPreset]
    ) -> [PromptPreset] {
        var presetsByID = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })

        for preset in rhs {
            if let existing = presetsByID[preset.id], existing.updatedAt >= preset.updatedAt {
                continue
            }

            presetsByID[preset.id] = preset
        }

        return PromptPreset.resolvedLibrary(from: Array(presetsByID.values))
    }

    private static func sortedPinnedMemories(_ items: [PinnedMemoryItem]) -> [PinnedMemoryItem] {
        items.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

actor ICloudConversationSyncService {
    nonisolated let isEnabled: Bool
    nonisolated let resolvedRootURL: URL?

    private let repository: ConversationRepository?

    init(
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let rootURL {
            let repository = ConversationRepository(
                configuration: configuration,
                rootURL: rootURL,
                fileManager: fileManager
            )
            self.repository = repository
            self.isEnabled = true
            self.resolvedRootURL = repository.resolvedRootURL
            return
        }

        guard let containerIdentifier = configuration?.iCloudContainerIdentifier?.nonEmptyTrimmed,
              let ubiquityContainerURL = fileManager.url(
                forUbiquityContainerIdentifier: containerIdentifier
              )
        else {
            self.repository = nil
            self.isEnabled = false
            self.resolvedRootURL = nil
            return
        }

        let rootURL = ubiquityContainerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("AIChatStore", isDirectory: true)
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: rootURL,
            fileManager: fileManager
        )
        self.repository = repository
        self.isEnabled = true
        self.resolvedRootURL = repository.resolvedRootURL
    }

    func reconcile(localState: ConversationSyncStoreState) async throws -> ConversationSyncStoreState {
        guard let repository else {
            return localState
        }

        let remoteState = try await loadState(from: repository)
        let mergedState = ConversationSyncStoreState.merged(local: localState, remote: remoteState)
        try await persist(
            mergedState,
            to: repository,
            deletingRemoteConversationIDs: Set(remoteState.conversations.map(\.id))
        )
        return mergedState
    }

    func fetchState() async throws -> ConversationSyncStoreState? {
        guard let repository else {
            return nil
        }

        return try await loadState(from: repository)
    }

    private func loadState(from repository: ConversationRepository) async throws -> ConversationSyncStoreState {
        ConversationSyncStoreState(
            conversations: try await repository.loadConversations(),
            deletedConversationTombstones: try await repository.loadDeletedConversationTombstones(),
            globalPinnedMemories: try await repository.loadGlobalPinnedMemories(),
            promptPresets: try await repository.loadPromptPresets()
        )
    }

    private func persist(
        _ state: ConversationSyncStoreState,
        to repository: ConversationRepository,
        deletingRemoteConversationIDs remoteConversationIDs: Set<UUID>
    ) async throws {
        let survivingConversationIDs = Set(state.conversations.map(\.id))

        for conversation in state.conversations {
            _ = try await repository.save(conversation)
        }

        for conversationID in remoteConversationIDs.subtracting(survivingConversationIDs) {
            try await repository.deleteConversation(id: conversationID)
        }

        try await repository.saveDeletedConversationTombstones(state.deletedConversationTombstones)
        try await repository.saveGlobalPinnedMemories(state.globalPinnedMemories)
        try await repository.savePromptPresets(state.promptPresets)
    }
}

private struct DeletedConversationDigestEntry: Codable, Hashable {
    let id: UUID
    let deletedAt: Date

    static func sortsByMostRecentFirst(
        _ lhs: DeletedConversationDigestEntry,
        _ rhs: DeletedConversationDigestEntry
    ) -> Bool {
        if lhs.deletedAt == rhs.deletedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return lhs.deletedAt > rhs.deletedAt
    }
}

private struct DigestPayload: Codable, Hashable {
    let conversations: [ConversationThread]
    let deletedConversationTombstones: [DeletedConversationDigestEntry]
    let globalPinnedMemories: [PinnedMemoryItem]
    let promptPresets: [PromptPreset]
}

private extension ConversationThread {
    var digestSanitizedCopy: ConversationThread {
        var sanitizedConversation = self

        for messageIndex in sanitizedConversation.messages.indices {
            for attachmentIndex in sanitizedConversation.messages[messageIndex].attachments.indices {
                let dataCount = UInt64(
                    sanitizedConversation.messages[messageIndex].attachments[attachmentIndex].data.count
                ).bigEndian
                sanitizedConversation.messages[messageIndex].attachments[attachmentIndex].data = withUnsafeBytes(
                    of: dataCount
                ) { Data($0) }
            }
        }

        return sanitizedConversation
    }

    var syncRichnessScore: [Int] {
        [
            messages.count,
            messages.reduce(into: 0) { total, message in
                total += message.attachments.count
            },
            messages.reduce(into: 0) { total, message in
                total += message.attachments.reduce(into: 0) { attachmentTotal, attachment in
                    if attachment.data.isEmpty == false {
                        attachmentTotal += 1
                    }
                }
            },
            messages.reduce(into: 0) { total, message in
                total += message.text.count
            }
        ]
    }

    var syncDigestSeed: String {
        digestSanitizedCopy.messages
            .map { message in
                let attachmentIDs = message.attachments.map(\.id.uuidString).joined(separator: ",")
                return [
                    message.id.uuidString,
                    message.createdAt.timeIntervalSince1970.description,
                    message.status.rawValue,
                    message.text,
                    attachmentIDs
                ].joined(separator: "|")
            }
            .joined(separator: "||")
    }
}
