//
//  ConversationStoreModels.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/20.
//

import Foundation
import SwiftData

@Model
final class ConversationStoreMetadataRecord {
    @Attribute(.unique) var key: String
    var schemaVersion: Int
    var legacyImportCompletedAt: Date?

    init(
        key: String = "primary",
        schemaVersion: Int,
        legacyImportCompletedAt: Date? = nil
    ) {
        self.key = key
        self.schemaVersion = schemaVersion
        self.legacyImportCompletedAt = legacyImportCompletedAt
    }
}

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var aiConfigurationData: Data?
    var focusStateData: Data?
    @Relationship(deleteRule: .cascade, inverse: \ConversationMessageRecord.conversation)
    var messages: [ConversationMessageRecord]
    @Relationship(deleteRule: .cascade, inverse: \ConversationMemoryRecord.conversation)
    var memoryItems: [ConversationMemoryRecord]
    @Relationship(deleteRule: .cascade, inverse: \ConversationPinnedMemoryRecord.conversation)
    var pinnedMemories: [ConversationPinnedMemoryRecord]
    @Relationship(deleteRule: .cascade, inverse: \ConversationArchiveSegmentRecord.conversation)
    var archiveSegments: [ConversationArchiveSegmentRecord]

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        isFavorite: Bool,
        aiConfigurationData: Data? = nil,
        focusStateData: Data? = nil,
        messages: [ConversationMessageRecord] = [],
        memoryItems: [ConversationMemoryRecord] = [],
        pinnedMemories: [ConversationPinnedMemoryRecord] = [],
        archiveSegments: [ConversationArchiveSegmentRecord] = []
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
final class ConversationMessageRecord {
    var id: UUID
    var roleRawValue: String
    var text: String
    var thoughtSummary: String?
    var modelResponsePartsData: Data?
    var createdAt: Date
    var statusRawValue: String
    var sortIndex: Int
    var conversation: ConversationRecord?
    @Relationship(deleteRule: .cascade, inverse: \ConversationAttachmentRecord.message)
    var attachments: [ConversationAttachmentRecord]

    init(
        id: UUID,
        roleRawValue: String,
        text: String,
        thoughtSummary: String?,
        modelResponsePartsData: Data?,
        createdAt: Date,
        statusRawValue: String,
        sortIndex: Int,
        conversation: ConversationRecord? = nil,
        attachments: [ConversationAttachmentRecord] = []
    ) {
        self.id = id
        self.roleRawValue = roleRawValue
        self.text = text
        self.thoughtSummary = thoughtSummary
        self.modelResponsePartsData = modelResponsePartsData
        self.createdAt = createdAt
        self.statusRawValue = statusRawValue
        self.sortIndex = sortIndex
        self.conversation = conversation
        self.attachments = attachments
    }
}

@Model
final class ConversationAttachmentRecord {
    var id: UUID
    var kindRawValue: String
    var filename: String
    var mimeType: String
    @Attribute(.externalStorage) var data: Data
    var blobFilename: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var durationSeconds: Double?
    var sortIndex: Int
    var message: ConversationMessageRecord?

    init(
        id: UUID,
        kindRawValue: String,
        filename: String,
        mimeType: String,
        data: Data,
        blobFilename: String?,
        pixelWidth: Int?,
        pixelHeight: Int?,
        durationSeconds: Double?,
        sortIndex: Int,
        message: ConversationMessageRecord? = nil
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.blobFilename = blobFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
        self.sortIndex = sortIndex
        self.message = message
    }
}

@Model
final class ConversationMemoryRecord {
    var id: UUID
    var text: String
    var keywordsData: Data
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationRecord?

    init(
        id: UUID,
        text: String,
        keywordsData: Data,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationRecord? = nil
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
final class ConversationPinnedMemoryRecord {
    var id: UUID
    var text: String
    var keywordsData: Data
    var scopeRawValue: String
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationRecord?

    init(
        id: UUID,
        text: String,
        keywordsData: Data,
        scopeRawValue: String,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationRecord? = nil
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
final class ConversationArchiveSegmentRecord {
    var id: UUID
    var title: String
    var summary: String
    var keywordsData: Data
    var openLoopsData: Data
    var sourceMessageIDsData: Data
    var updatedAt: Date
    var sortIndex: Int
    var conversation: ConversationRecord?

    init(
        id: UUID,
        title: String,
        summary: String,
        keywordsData: Data,
        openLoopsData: Data,
        sourceMessageIDsData: Data,
        updatedAt: Date,
        sortIndex: Int,
        conversation: ConversationRecord? = nil
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
final class GlobalPinnedMemoryRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    var keywordsData: Data
    var scopeRawValue: String
    var sourceMessageIDsData: Data
    var updatedAt: Date

    init(
        id: UUID,
        text: String,
        keywordsData: Data,
        scopeRawValue: String,
        sourceMessageIDsData: Data,
        updatedAt: Date
    ) {
        self.id = id
        self.text = text
        self.keywordsData = keywordsData
        self.scopeRawValue = scopeRawValue
        self.sourceMessageIDsData = sourceMessageIDsData
        self.updatedAt = updatedAt
    }
}

@Model
final class PromptPresetRecord {
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
final class DeletedConversationTombstoneRecord {
    @Attribute(.unique) var id: UUID
    var deletedAt: Date

    init(id: UUID, deletedAt: Date) {
        self.id = id
        self.deletedAt = deletedAt
    }
}
