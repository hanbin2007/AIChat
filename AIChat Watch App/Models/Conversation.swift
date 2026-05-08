//
//  Conversation.swift
//  AIChat Watch App
//
//  V2 domain model — pure value types decoupled from SwiftData
//  entities. ViewModels read these; `ConversationPersistence`
//  translates to/from `ConversationEntity`.
//
//  Names intentionally short (`Conversation`/`Message`/`Attachment`)
//  to read naturally in MVVM call sites. Legacy types (`ChatMessage`,
//  `ConversationThread`, `ChatAttachment`) keep their longer names
//  until Phase 5 deletes them.
//

import Foundation

enum MessageRole: String, Codable, Hashable, Sendable {
    case user
    case assistant
    case system
}

enum MessageStatus: String, Codable, Hashable, Sendable {
    case pending
    case streaming
    case complete
    case failed
    case cancelled
}

enum AttachmentKind: String, Codable, Hashable, Sendable {
    case image
    case audio
    case file
}

struct Attachment: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var kind: AttachmentKind
    var filename: String
    var mimeType: String
    /// Inline payload. `AttachmentEntity.data` uses `.externalStorage`
    /// so SwiftData spills it to a side file — the in-memory
    /// representation here stays a `Data` for ergonomic access.
    var data: Data
    var pixelWidth: Int?
    var pixelHeight: Int?
    var durationSeconds: Double?
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        kind: AttachmentKind,
        filename: String,
        mimeType: String,
        data: Data,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        durationSeconds: Double? = nil,
        sortIndex: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
        self.sortIndex = sortIndex
    }
}

struct Message: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var role: MessageRole
    var text: String
    var thoughtSummary: String?
    /// Encoded model-output parts (e.g. relay `model_content`). Kept as
    /// raw `Data` so the domain model doesn't depend on the relay DTOs.
    var modelContentData: Data?
    var status: MessageStatus
    var createdAt: Date
    var sortIndex: Int
    var attachments: [Attachment]

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        thoughtSummary: String? = nil,
        modelContentData: Data? = nil,
        status: MessageStatus = .complete,
        createdAt: Date = Date(),
        sortIndex: Int = 0,
        attachments: [Attachment] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thoughtSummary = thoughtSummary
        self.modelContentData = modelContentData
        self.status = status
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.attachments = attachments
    }
}

struct Conversation: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    /// Encoded `ConversationAIConfiguration` (legacy struct) — the
    /// V2 schema treats it as opaque so we don't have to re-thread the
    /// AI config every time the user tweaks a knob.
    var aiConfigurationData: Data?
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        aiConfigurationData: Data? = nil,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.aiConfigurationData = aiConfigurationData
        self.messages = messages
    }
}
