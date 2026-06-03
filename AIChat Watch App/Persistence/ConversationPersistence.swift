//
//  ConversationPersistence.swift
//  AIChat Watch App
//
//  Actor wrapping the V2 SwiftData container. Round-trips
//  `ConversationThread` (the canonical legacy value type) ↔
//  `ConversationEntity` so ViewModels never touch `ModelContext`.
//
//  Exposes an `AsyncStream<[ConversationThread]>` for list-view
//  ViewModels — registration is synchronous on the actor so any
//  mutation issued *after* `await stream()` returns is guaranteed to
//  reach the stream.
//

import Foundation
import SwiftData

actor ConversationPersistence {
    private let container: ModelContainer
    private let context: ModelContext
    private var subscribers: [UUID: AsyncStream<[ConversationThread]>.Continuation] = [:]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Reads

    func loadAll() throws -> [ConversationThread] {
        let descriptor = FetchDescriptor<ConversationEntity>(
            sortBy: [
                SortDescriptor(\ConversationEntity.updatedAt, order: .reverse),
                SortDescriptor(\ConversationEntity.createdAt, order: .reverse)
            ]
        )
        let entities = try context.fetch(descriptor)
        return entities.map { thread(from: $0) }
    }

    func conversation(id: UUID) throws -> ConversationThread? {
        try fetchEntity(id: id).map { thread(from: $0) }
    }

    func loadGlobalPinnedMemories() throws -> [PinnedMemoryItem] {
        // Global pins live in the per-conversation pinned table with
        // `scope == .global` and a `nil` conversation relationship. We
        // store them separately for query convenience but the V2
        // schema only has one pinned table — global pins are rows
        // with no conversation. We materialize them here.
        let descriptor = FetchDescriptor<PinnedMemoryEntity>(
            predicate: #Predicate { $0.conversation == nil }
        )
        let entities = try context.fetch(descriptor)
        return entities
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap(pinnedMemoryItem(from:))
    }

    func loadPromptPresets() throws -> [PromptPreset] {
        let descriptor = FetchDescriptor<PromptPresetEntity>(
            sortBy: [
                SortDescriptor(\PromptPresetEntity.updatedAt, order: .reverse)
            ]
        )
        let entities = try context.fetch(descriptor)
        return entities.compactMap(promptPreset(from:))
    }

    // MARK: - Mutations

    /// Insert-or-update; replaces persisted message + memory + pinned
    /// + archive lists with the supplied ones. Caller advances
    /// `updatedAt` to bubble the conversation in the list.
    @discardableResult
    func upsert(_ thread: ConversationThread) throws -> ConversationThread {
        let entity: ConversationEntity
        if let existing = try fetchEntity(id: thread.id) {
            entity = existing
            entity.title = thread.title
            entity.createdAt = thread.createdAt
            entity.updatedAt = thread.updatedAt
            entity.isFavorite = thread.isFavorite
            entity.aiConfigurationData = encodeIfPresent(thread.aiConfiguration)
            entity.focusStateData = encodeIfPresent(thread.focusState)
            for message in entity.messages { context.delete(message) }
            for memory in entity.memoryItems { context.delete(memory) }
            for pinned in entity.pinnedMemories { context.delete(pinned) }
            for archive in entity.archiveSegments { context.delete(archive) }
            entity.messages = []
            entity.memoryItems = []
            entity.pinnedMemories = []
            entity.archiveSegments = []
        } else {
            entity = ConversationEntity(
                id: thread.id,
                title: thread.title,
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                isFavorite: thread.isFavorite,
                aiConfigurationData: encodeIfPresent(thread.aiConfiguration),
                focusStateData: encodeIfPresent(thread.focusState)
            )
            context.insert(entity)
        }

        for (index, message) in thread.messages.enumerated() {
            let messageEntity = makeMessageEntity(from: message, sortIndex: index, parent: entity)
            entity.messages.append(messageEntity)
            context.insert(messageEntity)
        }
        for (index, item) in thread.memoryItems.enumerated() {
            let memoryEntity = MemoryItemEntity(
                id: item.id,
                text: item.text,
                keywordsData: encodeArray(item.keywords),
                sourceMessageIDsData: encodeArray(item.sourceMessageIDs.map { $0.uuidString }),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.memoryItems.append(memoryEntity)
            context.insert(memoryEntity)
        }
        for (index, item) in thread.pinnedMemories.enumerated() {
            let pinnedEntity = PinnedMemoryEntity(
                id: item.id,
                text: item.text,
                keywordsData: encodeArray(item.keywords),
                scopeRawValue: item.scope.rawValue,
                sourceMessageIDsData: encodeArray(item.sourceMessageIDs.map { $0.uuidString }),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.pinnedMemories.append(pinnedEntity)
            context.insert(pinnedEntity)
        }
        for (index, segment) in thread.archiveSegments.enumerated() {
            let archiveEntity = ArchiveSegmentEntity(
                id: segment.id,
                title: segment.title,
                summary: segment.summary,
                keywordsData: encodeArray(segment.keywords),
                openLoopsData: encodeArray(segment.openLoops),
                sourceMessageIDsData: encodeArray(segment.sourceMessageIDs.map { $0.uuidString }),
                updatedAt: segment.updatedAt,
                sortIndex: index,
                conversation: entity
            )
            entity.archiveSegments.append(archiveEntity)
            context.insert(archiveEntity)
        }

        try context.save()
        let snapshot = self.thread(from: entity)
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

    func saveGlobalPinnedMemories(_ items: [PinnedMemoryItem]) throws {
        // Replace all global pins atomically.
        let descriptor = FetchDescriptor<PinnedMemoryEntity>(
            predicate: #Predicate { $0.conversation == nil }
        )
        let existing = try context.fetch(descriptor)
        for entity in existing { context.delete(entity) }
        for (index, item) in items.enumerated() {
            let entity = PinnedMemoryEntity(
                id: item.id,
                text: item.text,
                keywordsData: encodeArray(item.keywords),
                scopeRawValue: item.scope.rawValue,
                sourceMessageIDsData: encodeArray(item.sourceMessageIDs.map { $0.uuidString }),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: nil
            )
            context.insert(entity)
        }
        try context.save()
    }

    func savePromptPresets(_ presets: [PromptPreset]) throws {
        // Replace all presets atomically.
        let descriptor = FetchDescriptor<PromptPresetEntity>()
        let existing = try context.fetch(descriptor)
        for entity in existing { context.delete(entity) }
        for preset in presets {
            let entity = PromptPresetEntity(
                id: preset.id,
                kindRawValue: preset.kind.rawValue,
                title: preset.title,
                content: preset.content,
                isBuiltIn: preset.isBuiltIn,
                createdAt: preset.createdAt,
                updatedAt: preset.updatedAt
            )
            context.insert(entity)
        }
        try context.save()
    }

    // MARK: - Subscription

    func stream() -> AsyncStream<[ConversationThread]> {
        let (stream, continuation) = AsyncStream<[ConversationThread]>.makeStream()
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

    func refresh() throws {
        try notifySubscribers()
    }

    private func removeSubscriber(_ token: UUID) {
        subscribers.removeValue(forKey: token)
    }

    private func notifySubscribers() throws {
        guard !subscribers.isEmpty else { return }
        let snapshot = try loadAll()
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - Helpers — fetch

    private func fetchEntity(id: UUID) throws -> ConversationEntity? {
        let descriptor = FetchDescriptor<ConversationEntity>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Helpers — encode/decode

    private func encodeIfPresent<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? encoder.encode(value)
    }

    private func decodeIfPresent<T: Decodable>(_ data: Data?, as type: T.Type) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encodeArray<T: Encodable>(_ array: [T]) -> Data {
        (try? encoder.encode(array)) ?? Data()
    }

    private func decodeArray<T: Decodable>(_ data: Data, as type: T.Type) -> [T] {
        guard !data.isEmpty else { return [] }
        return (try? decoder.decode([T].self, from: data)) ?? []
    }

    // MARK: - Helpers — entity → domain

    private func thread(from entity: ConversationEntity) -> ConversationThread {
        let messages = entity.messages
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { message(from: $0) }
        let memoryItems = entity.memoryItems
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap(memoryItem(from:))
        let pinnedMemories = entity.pinnedMemories
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap(pinnedMemoryItem(from:))
        let archiveSegments = entity.archiveSegments
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap(archiveSegment(from:))

        return ConversationThread(
            id: entity.id,
            title: entity.title,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            isFavorite: entity.isFavorite,
            messages: messages,
            aiConfiguration: decodeIfPresent(entity.aiConfigurationData, as: ConversationAIConfiguration.self),
            focusState: decodeIfPresent(entity.focusStateData, as: ConversationFocusState.self),
            memoryItems: memoryItems,
            pinnedMemories: pinnedMemories,
            archiveSegments: archiveSegments
        )
    }

    private func message(from entity: MessageEntity) -> ChatMessage {
        let attachments = entity.attachments
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(attachment(from:))
        let modelResponseParts = decodeIfPresent(entity.modelContentData, as: [GeminiPartPayload].self)
        return ChatMessage(
            id: entity.id,
            role: ChatRole(rawValue: entity.roleRawValue) ?? .assistant,
            text: entity.text,
            thoughtSummary: entity.thoughtSummary,
            modelResponseParts: modelResponseParts,
            createdAt: entity.createdAt,
            attachments: attachments,
            status: ChatMessageStatus(rawValue: entity.statusRawValue) ?? .sent
        )
    }

    private func attachment(from entity: AttachmentEntity) -> ChatAttachment {
        ChatAttachment(
            id: entity.id,
            kind: ChatAttachmentKind(rawValue: entity.kindRawValue) ?? .image,
            filename: entity.filename,
            mimeType: entity.mimeType,
            data: entity.data,
            pixelWidth: entity.pixelWidth,
            pixelHeight: entity.pixelHeight,
            durationSeconds: entity.durationSeconds
        )
    }

    private func memoryItem(from entity: MemoryItemEntity) -> ConversationMemoryItem? {
        let keywords = decodeArray(entity.keywordsData, as: String.self)
        let sourceIDs = decodeArray(entity.sourceMessageIDsData, as: String.self)
            .compactMap(UUID.init(uuidString:))
        return ConversationMemoryItem(
            id: entity.id,
            text: entity.text,
            keywords: keywords,
            sourceMessageIDs: sourceIDs,
            updatedAt: entity.updatedAt
        )
    }

    private func pinnedMemoryItem(from entity: PinnedMemoryEntity) -> PinnedMemoryItem? {
        let scope = PinnedMemoryScope(rawValue: entity.scopeRawValue) ?? .conversation
        let keywords = decodeArray(entity.keywordsData, as: String.self)
        let sourceIDs = decodeArray(entity.sourceMessageIDsData, as: String.self)
            .compactMap(UUID.init(uuidString:))
        return PinnedMemoryItem(
            id: entity.id,
            text: entity.text,
            keywords: keywords,
            scope: scope,
            sourceMessageIDs: sourceIDs,
            updatedAt: entity.updatedAt
        )
    }

    private func archiveSegment(from entity: ArchiveSegmentEntity) -> ConversationArchiveSegment? {
        let keywords = decodeArray(entity.keywordsData, as: String.self)
        let openLoops = decodeArray(entity.openLoopsData, as: String.self)
        let sourceIDs = decodeArray(entity.sourceMessageIDsData, as: String.self)
            .compactMap(UUID.init(uuidString:))
        return ConversationArchiveSegment(
            id: entity.id,
            title: entity.title,
            summary: entity.summary,
            keywords: keywords,
            openLoops: openLoops,
            sourceMessageIDs: sourceIDs,
            updatedAt: entity.updatedAt
        )
    }

    private func promptPreset(from entity: PromptPresetEntity) -> PromptPreset? {
        guard let kind = PromptPresetKind(rawValue: entity.kindRawValue) else { return nil }
        return PromptPreset(
            id: entity.id,
            kind: kind,
            title: entity.title,
            content: entity.content,
            isBuiltIn: entity.isBuiltIn,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt
        )
    }

    // MARK: - Helpers — domain → entity (messages only; the rest are
    // built inline in `upsert` because they're flat lists)

    private func makeMessageEntity(
        from message: ChatMessage,
        sortIndex: Int,
        parent: ConversationEntity
    ) -> MessageEntity {
        let modelContentData = encodeIfPresent(message.modelResponseParts)
        let entity = MessageEntity(
            id: message.id,
            roleRawValue: message.role.rawValue,
            text: message.text,
            thoughtSummary: message.thoughtSummary,
            modelContentData: modelContentData,
            statusRawValue: message.status.rawValue,
            createdAt: message.createdAt,
            sortIndex: sortIndex,
            conversation: parent
        )
        for (index, attachment) in message.attachments.enumerated() {
            let attachmentEntity = AttachmentEntity(
                id: attachment.id,
                kindRawValue: attachment.kind.rawValue,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                data: attachment.data,
                pixelWidth: attachment.pixelWidth,
                pixelHeight: attachment.pixelHeight,
                durationSeconds: attachment.durationSeconds,
                sortIndex: index,
                message: entity
            )
            entity.attachments.append(attachmentEntity)
            context.insert(attachmentEntity)
        }
        return entity
    }
}
