//
//  AIChatSchemaV2.swift
//  AIChat Watch App
//
//  V2 SwiftData schema for the relay-only Watch client. Entities are
//  renamed (`*Entity`) so they can coexist with V1's `*Record` types
//  during the rewrite without symbol collisions; once the cutover
//  lands and the V1→V2 migration ships, V1 types get deleted.
//
//  Persisted blobs (attachment data, memory keyword arrays) match V1
//  conventions to make the future migration plan a straight field
//  copy.
//

import Foundation
import SwiftData

/// Sentinel row keyed by `"primary"` — one per store. Tracks schema
/// version + the timestamp at which the V1→V2 migration finished, so
/// subsequent launches don't redo it.
@Model
final class StoreMetadataEntity {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var migratedFromV1At: Date?

    init(key: String = "primary", schemaVersion: Int, migratedFromV1At: Date? = nil) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.migratedFromV1At = migratedFromV1At
    }
}

@Model
final class ConversationEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    /// Encoded `ConversationAIConfiguration` blob — kept as opaque
    /// `Data` so the schema doesn't churn each time a model
    /// preference is added.
    var aiConfigurationData: Data?
    /// Encoded `ConversationFocusState` blob.
    var focusStateData: Data?
    @Relationship(deleteRule: .cascade, inverse: \MessageEntity.conversation)
    var messages: [MessageEntity]
    @Relationship(deleteRule: .cascade, inverse: \MemoryItemEntity.conversation)
    var memoryItems: [MemoryItemEntity]
    @Relationship(deleteRule: .cascade, inverse: \PinnedMemoryEntity.conversation)
    var pinnedMemories: [PinnedMemoryEntity]
    @Relationship(deleteRule: .cascade, inverse: \ArchiveSegmentEntity.conversation)
    var archiveSegments: [ArchiveSegmentEntity]

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        isFavorite: Bool,
        aiConfigurationData: Data? = nil,
        focusStateData: Data? = nil,
        messages: [MessageEntity] = [],
        memoryItems: [MemoryItemEntity] = [],
        pinnedMemories: [PinnedMemoryEntity] = [],
        archiveSegments: [ArchiveSegmentEntity] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.aiConfigurationData = aiConfigurationData
        self.focusStateData = focusStateData
        self.messages = messages
        self.memoryItems = memoryItems
        self.pinnedMemories = pinnedMemories
        self.archiveSegments = archiveSegments
    }
}

@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var text: String
    var thoughtSummary: String?
    /// Encoded array of `RelayPartPayload` (model output parts) — kept
    /// opaque so adding new part kinds doesn't churn the schema.
    var modelContentData: Data?
    var statusRawValue: String
    var createdAt: Date
    var sortIndex: Int
    var conversation: ConversationEntity?
    @Relationship(deleteRule: .cascade, inverse: \AttachmentEntity.message)
    var attachments: [AttachmentEntity]

    init(
        id: UUID,
        roleRawValue: String,
        text: String,
        thoughtSummary: String? = nil,
        modelContentData: Data? = nil,
        statusRawValue: String,
        createdAt: Date,
        sortIndex: Int,
        conversation: ConversationEntity? = nil,
        attachments: [AttachmentEntity] = []
    ) {
        self.id = id
        self.roleRawValue = roleRawValue
        self.text = text
        self.thoughtSummary = thoughtSummary
        self.modelContentData = modelContentData
        self.statusRawValue = statusRawValue
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.conversation = conversation
        self.attachments = attachments
    }
}

@Model
final class AttachmentEntity {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var filename: String
    var mimeType: String
    @Attribute(.externalStorage) var data: Data
    var pixelWidth: Int?
    var pixelHeight: Int?
    var durationSeconds: Double?
    var sortIndex: Int
    var message: MessageEntity?

    init(
        id: UUID,
        kindRawValue: String,
        filename: String,
        mimeType: String,
        data: Data,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        durationSeconds: Double? = nil,
        sortIndex: Int,
        message: MessageEntity? = nil
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
        self.sortIndex = sortIndex
        self.message = message
    }
}

@Model
final class MemoryItemEntity {
    @Attribute(.unique) var id: UUID
    var text: String
    var keywordsData: Data
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationEntity?

    init(
        id: UUID,
        text: String,
        keywordsData: Data,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationEntity? = nil
    ) {
        self.id = id
        self.text = text
        self.keywordsData = keywordsData
        self.sourceMessageIDsData = sourceMessageIDsData
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.conversation = conversation
    }
}

@Model
final class PinnedMemoryEntity {
    @Attribute(.unique) var id: UUID
    var text: String
    var keywordsData: Data
    /// `"conversation"` or `"global"`. Global pins reach across threads.
    var scopeRawValue: String
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationEntity?

    init(
        id: UUID,
        text: String,
        keywordsData: Data,
        scopeRawValue: String,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationEntity? = nil
    ) {
        self.id = id
        self.text = text
        self.keywordsData = keywordsData
        self.scopeRawValue = scopeRawValue
        self.sourceMessageIDsData = sourceMessageIDsData
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.conversation = conversation
    }
}

@Model
final class ArchiveSegmentEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var keywordsData: Data
    var openLoopsData: Data
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationEntity?

    init(
        id: UUID,
        title: String,
        summary: String,
        keywordsData: Data,
        openLoopsData: Data,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.keywordsData = keywordsData
        self.openLoopsData = openLoopsData
        self.sourceMessageIDsData = sourceMessageIDsData
        self.updatedAt = updatedAt
        self.sortIndex = sortIndex
        self.conversation = conversation
    }
}

@Model
final class PromptPresetEntity {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var title: String
    var content: String
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        kindRawValue: String,
        title: String,
        content: String,
        isBuiltIn: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.title = title
        self.content = content
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class DeletedTombstoneEntity {
    @Attribute(.unique) var id: UUID
    var deletedAt: Date

    init(id: UUID, deletedAt: Date) {
        self.id = id
        self.deletedAt = deletedAt
    }
}

/// Mirrors the relay-issued `rk_*` key + last known account snapshot.
/// One row keyed by `"primary"`; offline launches read it for cached
/// balance + plan info.
@Model
final class RelayAccountCacheEntity {
    @Attribute(.unique) var key: String
    var keyValue: String?
    /// Encoded `RelayAccountStatusResponse`.
    var accountStatusData: Data?
    var lastRefreshedAt: Date?

    init(
        key: String = "primary",
        keyValue: String? = nil,
        accountStatusData: Data? = nil,
        lastRefreshedAt: Date? = nil
    ) {
        self.key = key
        self.keyValue = keyValue
        self.accountStatusData = accountStatusData
        self.lastRefreshedAt = lastRefreshedAt
    }
}

/// Cached billing catalog + metering policy for offline rendering of
/// the purchase sheet's plan list and the low-balance threshold.
@Model
final class BillingPolicyCacheEntity {
    @Attribute(.unique) var key: String
    /// Encoded `RelayCatalogResponse`.
    var catalogData: Data?
    var lastRefreshedAt: Date?

    init(
        key: String = "primary",
        catalogData: Data? = nil,
        lastRefreshedAt: Date? = nil
    ) {
        self.key = key
        self.catalogData = catalogData
        self.lastRefreshedAt = lastRefreshedAt
    }
}

enum AIChatSchemaV2 {
    static let schemaVersion = 2

    static let entities: [any PersistentModel.Type] = [
        StoreMetadataEntity.self,
        ConversationEntity.self,
        MessageEntity.self,
        AttachmentEntity.self,
        MemoryItemEntity.self,
        PinnedMemoryEntity.self,
        ArchiveSegmentEntity.self,
        PromptPresetEntity.self,
        DeletedTombstoneEntity.self,
        RelayAccountCacheEntity.self,
        BillingPolicyCacheEntity.self
    ]

    static func makeSchema() -> Schema {
        Schema(entities)
    }
}
