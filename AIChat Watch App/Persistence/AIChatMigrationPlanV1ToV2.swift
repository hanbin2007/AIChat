//
//  AIChatMigrationPlanV1ToV2.swift
//  AIChat Watch App
//
//  One-shot copy from the V1 SwiftData store
//  (`ConversationStore.sqlite`, schema in `ConversationStoreModels.swift`)
//  into the V2 store (`AIChatStoreV2.sqlite`, schema in
//  `AIChatSchemaV2.swift`).
//
//  Triggered at startup by `ConversationPersistence.bootstrap()`. The
//  V1 schema files (`ConversationStoreModels.swift`) stay in the
//  build at least one release cycle as a safety net; once telemetry
//  confirms migration succeeded for the field they can be deleted.
//

import Foundation
import SwiftData

enum AIChatMigrationPlanV1ToV2 {

    /// Result reported back to callers so they can log / surface a
    /// banner if migration partially failed.
    struct Outcome: Equatable {
        var migratedConversations: Int
        var migratedPresets: Int
        var migratedGlobalPins: Int
        var skipped: Bool
        var failureReason: String?
    }

    /// Returns `true` if V1 store exists at the resolved root; lets
    /// callers skip the whole migration path on fresh installs.
    static func v1StoreExists(rootURL: URL, fileManager: FileManager = .default) -> Bool {
        let url = v1StoreURL(rootURL: rootURL)
        return fileManager.fileExists(atPath: url.path)
    }

    /// Migrates V1 → V2 if not already done. Idempotent: if
    /// `StoreMetadataEntity.migratedFromV1At` is set, returns
    /// `Outcome(skipped: true)` immediately.
    @discardableResult
    static func migrateIfNeeded(
        v2Container: ModelContainer,
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> Outcome {
        let v2Context = ModelContext(v2Container)

        // Already migrated?
        if let metadata = try? fetchMetadata(in: v2Context),
           metadata.migratedFromV1At != nil {
            return Outcome(
                migratedConversations: 0,
                migratedPresets: 0,
                migratedGlobalPins: 0,
                skipped: true,
                failureReason: nil
            )
        }

        guard v1StoreExists(rootURL: rootURL, fileManager: fileManager) else {
            // No V1 — fresh install. Mark migrated so we don't retry
            // every launch.
            markMigrated(in: v2Context)
            return Outcome(
                migratedConversations: 0,
                migratedPresets: 0,
                migratedGlobalPins: 0,
                skipped: true,
                failureReason: nil
            )
        }

        // Open V1 read-only.
        let v1Container: ModelContainer
        do {
            v1Container = try makeV1Container(rootURL: rootURL)
        } catch {
            return Outcome(
                migratedConversations: 0,
                migratedPresets: 0,
                migratedGlobalPins: 0,
                skipped: false,
                failureReason: "V1 open failed: \(error.localizedDescription)"
            )
        }
        let v1Context = ModelContext(v1Container)

        var conversationCount = 0
        var presetCount = 0
        var globalPinCount = 0

        do {
            // Conversations + cascade.
            let v1Conversations = try v1Context.fetch(
                FetchDescriptor<ConversationRecord>(
                    sortBy: [SortDescriptor(\ConversationRecord.updatedAt, order: .forward)]
                )
            )
            for record in v1Conversations {
                let entity = makeV2Conversation(from: record, context: v2Context)
                v2Context.insert(entity)
                conversationCount += 1
            }

            // Prompt presets.
            let v1Presets = try v1Context.fetch(FetchDescriptor<PromptPresetRecord>())
            for record in v1Presets {
                v2Context.insert(
                    PromptPresetEntity(
                        id: record.id,
                        kindRawValue: record.kindRawValue,
                        title: record.title,
                        content: record.content,
                        isBuiltIn: record.isBuiltIn,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt
                    )
                )
                presetCount += 1
            }

            // Global pinned memories.
            let v1GlobalPins = try v1Context.fetch(FetchDescriptor<GlobalPinnedMemoryRecord>())
            for record in v1GlobalPins {
                v2Context.insert(
                    PinnedMemoryEntity(
                        id: record.id,
                        text: record.text,
                        keywordsData: record.keywordsData,
                        scopeRawValue: record.scopeRawValue,
                        sourceMessageIDsData: record.sourceMessageIDsData,
                        updatedAt: record.updatedAt,
                        sortIndex: 0,
                        conversation: nil
                    )
                )
                globalPinCount += 1
            }

            // Tombstones.
            let v1Tombstones = try v1Context.fetch(FetchDescriptor<DeletedConversationTombstoneRecord>())
            for record in v1Tombstones {
                v2Context.insert(DeletedTombstoneEntity(id: record.id, deletedAt: record.deletedAt))
            }

            try v2Context.save()
            markMigrated(in: v2Context)
            return Outcome(
                migratedConversations: conversationCount,
                migratedPresets: presetCount,
                migratedGlobalPins: globalPinCount,
                skipped: false,
                failureReason: nil
            )
        } catch {
            return Outcome(
                migratedConversations: conversationCount,
                migratedPresets: presetCount,
                migratedGlobalPins: globalPinCount,
                skipped: false,
                failureReason: error.localizedDescription
            )
        }
    }

    // MARK: - Private

    private static func v1StoreURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent("ConversationStore.sqlite", isDirectory: false)
    }

    private static func makeV1Container(rootURL: URL) throws -> ModelContainer {
        let schema = Schema([
            ConversationStoreMetadataRecord.self,
            ConversationRecord.self,
            ConversationMessageRecord.self,
            ConversationAttachmentRecord.self,
            ConversationMemoryRecord.self,
            ConversationPinnedMemoryRecord.self,
            ConversationArchiveSegmentRecord.self,
            GlobalPinnedMemoryRecord.self,
            PromptPresetRecord.self,
            DeletedConversationTombstoneRecord.self
        ])
        let configuration = ModelConfiguration(
            "ConversationStoreV1Read",
            schema: schema,
            url: v1StoreURL(rootURL: rootURL),
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func fetchMetadata(in context: ModelContext) throws -> StoreMetadataEntity? {
        let key = "primary"
        let descriptor = FetchDescriptor<StoreMetadataEntity>(
            predicate: #Predicate { $0.key == key }
        )
        return try context.fetch(descriptor).first
    }

    private static func markMigrated(in context: ModelContext) {
        do {
            if let existing = try fetchMetadata(in: context) {
                existing.migratedFromV1At = Date()
                existing.schemaVersion = AIChatSchemaV2.schemaVersion
            } else {
                context.insert(
                    StoreMetadataEntity(
                        schemaVersion: AIChatSchemaV2.schemaVersion,
                        migratedFromV1At: Date()
                    )
                )
            }
            try context.save()
        } catch {
            // Best-effort — the next launch will retry the whole
            // migration if metadata didn't get written.
        }
    }

    private static func makeV2Conversation(
        from record: ConversationRecord,
        context: ModelContext
    ) -> ConversationEntity {
        let entity = ConversationEntity(
            id: record.id,
            title: record.title,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isFavorite: record.isFavorite,
            aiConfigurationData: record.aiConfigurationData,
            focusStateData: record.focusStateData
        )
        for (index, message) in record.messages.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            let messageEntity = MessageEntity(
                id: message.id,
                roleRawValue: message.roleRawValue,
                text: message.text,
                thoughtSummary: message.thoughtSummary,
                modelContentData: message.modelResponsePartsData,
                statusRawValue: message.statusRawValue,
                createdAt: message.createdAt,
                sortIndex: index,
                conversation: entity
            )
            for (attachIndex, attachment) in message.attachments.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
                let attachmentEntity = AttachmentEntity(
                    id: attachment.id,
                    kindRawValue: attachment.kindRawValue,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data,
                    pixelWidth: attachment.pixelWidth,
                    pixelHeight: attachment.pixelHeight,
                    durationSeconds: attachment.durationSeconds,
                    sortIndex: attachIndex,
                    message: messageEntity
                )
                messageEntity.attachments.append(attachmentEntity)
                context.insert(attachmentEntity)
            }
            entity.messages.append(messageEntity)
            context.insert(messageEntity)
        }
        for (index, item) in record.memoryItems.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            let memoryEntity = MemoryItemEntity(
                id: item.id,
                text: item.text,
                keywordsData: item.keywordsData,
                sourceMessageIDsData: item.sourceMessageIDsData,
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.memoryItems.append(memoryEntity)
            context.insert(memoryEntity)
        }
        for (index, item) in record.pinnedMemories.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            let pinnedEntity = PinnedMemoryEntity(
                id: item.id,
                text: item.text,
                keywordsData: item.keywordsData,
                scopeRawValue: item.scopeRawValue,
                sourceMessageIDsData: item.sourceMessageIDsData,
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.pinnedMemories.append(pinnedEntity)
            context.insert(pinnedEntity)
        }
        for (index, segment) in record.archiveSegments.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            let archiveEntity = ArchiveSegmentEntity(
                id: segment.id,
                title: segment.title,
                summary: segment.summary,
                keywordsData: segment.keywordsData,
                openLoopsData: segment.openLoopsData,
                sourceMessageIDsData: segment.sourceMessageIDsData,
                updatedAt: segment.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.archiveSegments.append(archiveEntity)
            context.insert(archiveEntity)
        }
        return entity
    }
}
