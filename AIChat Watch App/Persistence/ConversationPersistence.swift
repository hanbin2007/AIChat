//
//  ConversationPersistence.swift
//  AIChat Watch App
//
//  Actor wrapping the V2 SwiftData container. Exposes value-type CRUD
//  for `Conversation` so callers stay off the SwiftData object graph,
//  and an `AsyncStream<[Conversation]>` that re-emits the full list
//  after every mutation — `ConversationListViewModel` subscribes once
//  and renders without ever touching `ModelContext`.
//
//  Mutations run on a single `ModelContext` owned by the actor; reads
//  also go through that context. Snapshots are derived eagerly so the
//  caller can hold them across actor boundaries.
//

import Foundation
import SwiftData

actor ConversationPersistence {
    private let container: ModelContainer
    private let context: ModelContext
    private var subscribers: [UUID: AsyncStream<[Conversation]>.Continuation] = [:]

    init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
    }

    // MARK: - Reads

    func loadAll() throws -> [Conversation] {
        let descriptor = FetchDescriptor<ConversationEntity>(
            sortBy: [
                SortDescriptor(\ConversationEntity.updatedAt, order: .reverse),
                SortDescriptor(\ConversationEntity.createdAt, order: .reverse)
            ]
        )
        let entities = try context.fetch(descriptor)
        return entities.map(Self.snapshot(from:))
    }

    func conversation(id: UUID) throws -> Conversation? {
        try fetchEntity(id: id).map(Self.snapshot(from:))
    }

    // MARK: - Mutations

    /// Insert-or-update; replaces the persisted message list with the
    /// supplied one. Caller is responsible for monotonically advancing
    /// `updatedAt` when they want the conversation to bubble to the top.
    @discardableResult
    func upsert(_ conversation: Conversation) throws -> Conversation {
        let entity: ConversationEntity
        if let existing = try fetchEntity(id: conversation.id) {
            entity = existing
            entity.title = conversation.title
            entity.createdAt = conversation.createdAt
            entity.updatedAt = conversation.updatedAt
            entity.isFavorite = conversation.isFavorite
            entity.aiConfigurationData = conversation.aiConfigurationData
            // Cascade delete handles the old children automatically when
            // we drop the relationship and replace.
            for message in entity.messages {
                context.delete(message)
            }
            entity.messages = []
        } else {
            entity = ConversationEntity(
                id: conversation.id,
                title: conversation.title,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                isFavorite: conversation.isFavorite,
                aiConfigurationData: conversation.aiConfigurationData
            )
            context.insert(entity)
        }

        for message in conversation.messages {
            let messageEntity = MessageEntity(
                id: message.id,
                roleRawValue: message.role.rawValue,
                text: message.text,
                thoughtSummary: message.thoughtSummary,
                modelContentData: message.modelContentData,
                statusRawValue: message.status.rawValue,
                createdAt: message.createdAt,
                sortIndex: message.sortIndex,
                conversation: entity
            )
            for attachment in message.attachments {
                let attachmentEntity = AttachmentEntity(
                    id: attachment.id,
                    kindRawValue: attachment.kind.rawValue,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data,
                    pixelWidth: attachment.pixelWidth,
                    pixelHeight: attachment.pixelHeight,
                    durationSeconds: attachment.durationSeconds,
                    sortIndex: attachment.sortIndex,
                    message: messageEntity
                )
                messageEntity.attachments.append(attachmentEntity)
                context.insert(attachmentEntity)
            }
            entity.messages.append(messageEntity)
            context.insert(messageEntity)
        }

        try context.save()
        let snapshot = Self.snapshot(from: entity)
        try notifySubscribers()
        return snapshot
    }

    func delete(id: UUID) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        context.delete(entity)
        let tombstone = DeletedTombstoneEntity(id: id, deletedAt: Date())
        context.insert(tombstone)
        try context.save()
        try notifySubscribers()
    }

    func setFavorite(id: UUID, isFavorite: Bool) throws {
        guard let entity = try fetchEntity(id: id) else { return }
        entity.isFavorite = isFavorite
        entity.updatedAt = Date()
        try context.save()
        try notifySubscribers()
    }

    // MARK: - Subscription

    /// Emits the current conversation list immediately and again after
    /// every mutation that goes through this actor. External (cross-
    /// process) edits do not trigger emissions — for those the caller
    /// must invoke `refresh()`.
    ///
    /// Registration and the initial snapshot are both synchronous
    /// inside the actor, so any mutation issued *after* `await stream()`
    /// returns is guaranteed to land in the stream.
    func stream() -> AsyncStream<[Conversation]> {
        let (stream, continuation) = AsyncStream<[Conversation]>.makeStream()
        let token = UUID()
        subscribers[token] = continuation
        if let snapshot = try? loadAll() {
            continuation.yield(snapshot)
        }
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeSubscriber(token)
            }
        }
        return stream
    }

    /// Force a re-emission to all subscribers — used after non-actor
    /// mutations (e.g. iCloud sync writes directly to the store).
    func refresh() throws {
        try notifySubscribers()
    }

    private func removeSubscriber(_ token: UUID) {
        subscribers.removeValue(forKey: token)
    }

    // MARK: - Helpers

    private func fetchEntity(id: UUID) throws -> ConversationEntity? {
        let descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func notifySubscribers() throws {
        guard !subscribers.isEmpty else { return }
        let snapshot = try loadAll()
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }

    private static func snapshot(from entity: ConversationEntity) -> Conversation {
        let messages = entity.messages
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(snapshot(from:))
        return Conversation(
            id: entity.id,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            isFavorite: entity.isFavorite,
            aiConfigurationData: entity.aiConfigurationData,
            messages: messages
        )
    }

    private static func snapshot(from entity: MessageEntity) -> Message {
        let attachments = entity.attachments
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(snapshot(from:))
        return Message(
            id: entity.id,
            role: MessageRole(rawValue: entity.roleRawValue) ?? .assistant,
            text: entity.text,
            thoughtSummary: entity.thoughtSummary,
            modelContentData: entity.modelContentData,
            status: MessageStatus(rawValue: entity.statusRawValue) ?? .complete,
            createdAt: entity.createdAt,
            sortIndex: entity.sortIndex,
            attachments: attachments
        )
    }

    private static func snapshot(from entity: AttachmentEntity) -> Attachment {
        Attachment(
            id: entity.id,
            kind: AttachmentKind(rawValue: entity.kindRawValue) ?? .file,
            filename: entity.filename,
            mimeType: entity.mimeType,
            data: entity.data,
            pixelWidth: entity.pixelWidth,
            pixelHeight: entity.pixelHeight,
            durationSeconds: entity.durationSeconds,
            sortIndex: entity.sortIndex
        )
    }
}
