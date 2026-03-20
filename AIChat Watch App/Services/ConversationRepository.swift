//
//  ConversationRepository.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import SwiftData

private struct LegacyDeletedConversationTombstone: Codable, Hashable {
    let id: UUID
    let deletedAt: Date
}

private struct LegacyConversationStoreState {
    var conversations: [ConversationThread]
    var deletedConversationTombstones: [UUID: Date]
    var globalPinnedMemories: [PinnedMemoryItem]
    var promptPresets: [PromptPreset]
}

private enum ConversationRepositoryError: LocalizedError {
    case storageInitializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .storageInitializationFailed(let reason):
            return "Failed to initialize conversation store: \(reason)"
        }
    }
}

actor ConversationRepository {
    private static let currentSchemaVersion = 1
    private static let metadataKey = "primary"
    private static let sqliteFilename = "ConversationStore.sqlite"
    private static let schema = Schema([
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

    nonisolated let storageDescription: String
    nonisolated let resolvedRootURL: URL
    nonisolated let attachmentsDirectoryURL: URL

    private let rootURL: URL
    private let attachmentsRootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let modelContainer: ModelContainer?
    private let initializationError: Error?
    private var hasPreparedStore = false

    init(
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let resolvedStorage = Self.defaultRootURL(
            fileManager: fileManager,
            appGroupIdentifier: configuration?.appGroupIdentifier,
            overrideRootURL: rootURL
        )
        self.rootURL = resolvedStorage.url
        self.attachmentsRootURL = resolvedStorage.url.appendingPathComponent("attachments", isDirectory: true)
        self.resolvedRootURL = resolvedStorage.url
        self.attachmentsDirectoryURL = self.attachmentsRootURL
        self.storageDescription = resolvedStorage.description

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()

        do {
            if fileManager.fileExists(atPath: resolvedStorage.url.path) == false {
                try fileManager.createDirectory(at: resolvedStorage.url, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: attachmentsRootURL.path) == false {
                try fileManager.createDirectory(at: attachmentsRootURL, withIntermediateDirectories: true)
            }

            let configuration = ModelConfiguration(
                "ConversationStore",
                schema: Self.schema,
                url: resolvedStorage.url.appendingPathComponent(Self.sqliteFilename, isDirectory: false),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            self.modelContainer = try ModelContainer(for: Self.schema, configurations: [configuration])
            self.initializationError = nil
        } catch {
            self.modelContainer = nil
            self.initializationError = ConversationRepositoryError.storageInitializationFailed(
                error.localizedDescription
            )
        }
    }

    func loadConversations() throws -> [ConversationThread] {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [
                SortDescriptor(\ConversationRecord.updatedAt, order: .reverse),
                SortDescriptor(\ConversationRecord.createdAt, order: .reverse)
            ]
        )
        let records = try context.fetch(descriptor)
        try materializeAttachmentExports(for: records)
        return records
            .map(makeConversation(from:))
            .sorted(by: ConversationThread.sortsByMostRecentFirst)
    }

    @discardableResult
    func save(_ conversation: ConversationThread) throws -> ConversationThread {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        let preparedConversation = preparedConversationForStorage(conversation)
        let existingRecord = try fetchConversationRecord(id: preparedConversation.id, in: context)
        let previousBlobFilenames = Set(existingRecord?.allAttachmentBlobFilenames ?? [])

        let record = existingRecord ?? ConversationRecord(
            id: preparedConversation.id,
            title: preparedConversation.title,
            createdAt: preparedConversation.createdAt,
            updatedAt: preparedConversation.updatedAt,
            isFavorite: preparedConversation.isFavorite
        )
        if existingRecord == nil {
            context.insert(record)
        }

        try replaceConversationRecord(record, with: preparedConversation, in: context)
        try context.save()
        try materializeAttachmentExports(for: record)
        try removeOrphanedExportBlobs(
            previousBlobFilenames.subtracting(Set(record.allAttachmentBlobFilenames)),
            in: context
        )
        return makeConversation(from: record)
    }

    func loadGlobalPinnedMemories() throws -> [PinnedMemoryItem] {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        let items = try context.fetch(FetchDescriptor<GlobalPinnedMemoryRecord>())
            .map(makePinnedMemoryItem(from:))
        return Self.sortedPinnedMemories(items)
    }

    func saveGlobalPinnedMemories(_ items: [PinnedMemoryItem]) throws {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        for record in try context.fetch(FetchDescriptor<GlobalPinnedMemoryRecord>()) {
            context.delete(record)
        }

        for item in items {
            context.insert(try makeGlobalPinnedMemoryRecord(from: item))
        }

        try context.save()
    }

    func loadPromptPresets() throws -> [PromptPreset] {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        let presets = try context.fetch(FetchDescriptor<PromptPresetRecord>())
            .map(makePromptPreset(from:))
        return PromptPreset.resolvedLibrary(from: presets)
    }

    func savePromptPresets(_ items: [PromptPreset]) throws {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        for record in try context.fetch(FetchDescriptor<PromptPresetRecord>()) {
            context.delete(record)
        }

        for item in items {
            context.insert(makePromptPresetRecord(from: item))
        }

        try context.save()
    }

    func loadDeletedConversationTombstones() throws -> [UUID: Date] {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        let records = try context.fetch(FetchDescriptor<DeletedConversationTombstoneRecord>())
        return Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.deletedAt) })
    }

    func saveDeletedConversationTombstones(_ items: [UUID: Date]) throws {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        for record in try context.fetch(FetchDescriptor<DeletedConversationTombstoneRecord>()) {
            context.delete(record)
        }

        for item in items {
            context.insert(DeletedConversationTombstoneRecord(id: item.key, deletedAt: item.value))
        }

        try context.save()
    }

    func deleteConversation(id: UUID) throws {
        let context = try makeContext()
        try prepareStoreIfNeeded(in: context)

        guard let record = try fetchConversationRecord(id: id, in: context) else {
            return
        }

        let removedBlobFilenames = Set(record.allAttachmentBlobFilenames)
        context.delete(record)
        try context.save()
        try removeOrphanedExportBlobs(removedBlobFilenames, in: context)
    }

    func importAttachmentBlob(
        from temporaryFileURL: URL,
        as blobFilename: String
    ) throws -> Data {
        try ensureDirectoryExists()

        let destinationURL = attachmentsRootURL.appendingPathComponent(blobFilename, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: temporaryFileURL, to: destinationURL)
        return try Data(contentsOf: destinationURL)
    }

    func hydrateAttachments(in conversation: ConversationThread) -> ConversationThread {
        var hydratedConversation = conversation

        for messageIndex in hydratedConversation.messages.indices {
            for attachmentIndex in hydratedConversation.messages[messageIndex].attachments.indices {
                let attachment = hydratedConversation.messages[messageIndex].attachments[attachmentIndex]
                guard attachment.data.isEmpty,
                      let blobFilename = attachment.blobFilename?.nonEmptyTrimmed
                else {
                    continue
                }

                let blobURL = attachmentsRootURL.appendingPathComponent(blobFilename, isDirectory: false)
                guard let data = try? Data(contentsOf: blobURL) else {
                    continue
                }

                hydratedConversation.messages[messageIndex].attachments[attachmentIndex].data = data
            }
        }

        return hydratedConversation
    }

    private func makeContext() throws -> ModelContext {
        if let initializationError {
            throw initializationError
        }

        guard let modelContainer else {
            throw ConversationRepositoryError.storageInitializationFailed("Missing model container.")
        }

        return ModelContext(modelContainer)
    }

    private func prepareStoreIfNeeded(in context: ModelContext) throws {
        guard hasPreparedStore == false else {
            return
        }

        try ensureDirectoryExists()
        let metadata = try fetchOrCreateMetadata(in: context)

        if metadata.legacyImportCompletedAt == nil {
            if try storeContainsSwiftDataRecords(in: context) == false,
               legacyStoreExists() {
                try importLegacyStore(into: context)
            }

            metadata.schemaVersion = Self.currentSchemaVersion
            metadata.legacyImportCompletedAt = .now
            try context.save()
        }

        hasPreparedStore = true
    }

    private func fetchOrCreateMetadata(in context: ModelContext) throws -> ConversationStoreMetadataRecord {
        let metadataKey = Self.metadataKey
        var descriptor = FetchDescriptor<ConversationStoreMetadataRecord>(
            predicate: #Predicate<ConversationStoreMetadataRecord> {
                $0.key == metadataKey
            }
        )
        descriptor.fetchLimit = 1

        if let metadata = try context.fetch(descriptor).first {
            return metadata
        }

        let metadata = ConversationStoreMetadataRecord(schemaVersion: Self.currentSchemaVersion)
        context.insert(metadata)
        return metadata
    }

    private func storeContainsSwiftDataRecords(in context: ModelContext) throws -> Bool {
        if try hasAnyRecords(of: ConversationRecord.self, in: context) {
            return true
        }

        if try hasAnyRecords(of: GlobalPinnedMemoryRecord.self, in: context) {
            return true
        }

        if try hasAnyRecords(of: PromptPresetRecord.self, in: context) {
            return true
        }

        return try hasAnyRecords(of: DeletedConversationTombstoneRecord.self, in: context)
    }

    private func hasAnyRecords<T: PersistentModel>(
        of type: T.Type,
        in context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    private func importLegacyStore(into context: ModelContext) throws {
        let legacyState = try loadLegacyStoreState()

        for conversation in legacyState.conversations {
            let record = ConversationRecord(
                id: conversation.id,
                title: conversation.title,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                isFavorite: conversation.isFavorite
            )
            context.insert(record)
            try replaceConversationRecord(record, with: conversation, in: context)
        }

        for item in legacyState.globalPinnedMemories {
            context.insert(try makeGlobalPinnedMemoryRecord(from: item))
        }

        for item in legacyState.promptPresets {
            context.insert(makePromptPresetRecord(from: item))
        }

        for item in legacyState.deletedConversationTombstones {
            context.insert(DeletedConversationTombstoneRecord(id: item.key, deletedAt: item.value))
        }
    }

    private func loadLegacyStoreState() throws -> LegacyConversationStoreState {
        LegacyConversationStoreState(
            conversations: try legacyLoadConversations(),
            deletedConversationTombstones: try legacyLoadDeletedConversationTombstones(),
            globalPinnedMemories: try legacyLoadGlobalPinnedMemories(),
            promptPresets: try legacyLoadPromptPresets()
        )
    }

    private func legacyStoreExists() -> Bool {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return false
        }

        return legacyConversationFileURLs().isEmpty == false ||
            fileManager.fileExists(atPath: globalPinnedMemoriesURL().path) ||
            fileManager.fileExists(atPath: promptPresetsURL().path) ||
            fileManager.fileExists(atPath: deletedConversationTombstonesURL().path)
    }

    private func legacyConversationFileURLs() -> [URL] {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return fileURLs.filter {
            $0.pathExtension == "json" &&
            $0.lastPathComponent.hasPrefix("_") == false
        }
    }

    private func legacyLoadConversations() throws -> [ConversationThread] {
        try legacyConversationFileURLs().map { url in
            let data = try Data(contentsOf: url)
            let conversation = try decoder.decode(ConversationThread.self, from: data)
            return preparedConversationForStorage(hydrateLegacyConversation(conversation))
        }
        .sorted(by: ConversationThread.sortsByMostRecentFirst)
    }

    private func hydrateLegacyConversation(_ conversation: ConversationThread) -> ConversationThread {
        hydrateAttachments(in: conversation)
    }

    private func legacyLoadGlobalPinnedMemories() throws -> [PinnedMemoryItem] {
        let url = globalPinnedMemoriesURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PinnedMemoryItem].self, from: data)
    }

    private func legacyLoadPromptPresets() throws -> [PromptPreset] {
        let url = promptPresetsURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PromptPreset].self, from: data)
    }

    private func legacyLoadDeletedConversationTombstones() throws -> [UUID: Date] {
        let url = deletedConversationTombstonesURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        let tombstones = try decoder.decode([LegacyDeletedConversationTombstone].self, from: data)
        return Dictionary(uniqueKeysWithValues: tombstones.map { ($0.id, $0.deletedAt) })
    }

    private func replaceConversationRecord(
        _ record: ConversationRecord,
        with conversation: ConversationThread,
        in context: ModelContext
    ) throws {
        record.title = conversation.title
        record.createdAt = conversation.createdAt
        record.updatedAt = conversation.updatedAt
        record.isFavorite = conversation.isFavorite
        record.aiConfigurationData = try encodeValue(conversation.aiConfiguration)
        record.focusStateData = try encodeValue(conversation.focusState)

        for message in record.messages {
            context.delete(message)
        }
        for memoryItem in record.memoryItems {
            context.delete(memoryItem)
        }
        for pinnedMemory in record.pinnedMemories {
            context.delete(pinnedMemory)
        }
        for archiveSegment in record.archiveSegments {
            context.delete(archiveSegment)
        }

        record.messages = []
        record.memoryItems = []
        record.pinnedMemories = []
        record.archiveSegments = []

        record.messages = try conversation.messages.enumerated().map { messageIndex, message in
            let messageRecord = ConversationMessageRecord(
                id: message.id,
                roleRawValue: message.role.rawValue,
                text: message.text,
                thoughtSummary: message.thoughtSummary?.nonEmptyTrimmed,
                modelResponsePartsData: try encodeValue(message.modelResponseParts),
                createdAt: message.createdAt,
                statusRawValue: message.status.rawValue,
                sortIndex: messageIndex,
                conversation: record
            )
            context.insert(messageRecord)
            messageRecord.attachments = message.attachments.enumerated().map { attachmentIndex, attachment in
                let attachmentRecord = ConversationAttachmentRecord(
                    id: attachment.id,
                    kindRawValue: attachment.kind.rawValue,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data,
                    blobFilename: attachment.blobFilename?.nonEmptyTrimmed,
                    pixelWidth: attachment.pixelWidth,
                    pixelHeight: attachment.pixelHeight,
                    durationSeconds: attachment.durationSeconds,
                    sortIndex: attachmentIndex,
                    message: messageRecord
                )
                context.insert(attachmentRecord)
                return attachmentRecord
            }
            return messageRecord
        }

        record.memoryItems = try conversation.memoryItems.enumerated().map { index, item in
            let memoryRecord = ConversationMemoryRecord(
                id: item.id,
                text: item.text,
                keywordsData: try encodeArray(item.keywords),
                sourceMessageIDsData: try encodeArray(item.sourceMessageIDs),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: record
            )
            context.insert(memoryRecord)
            return memoryRecord
        }

        record.pinnedMemories = try conversation.pinnedMemories.enumerated().map { index, item in
            let pinnedMemoryRecord = ConversationPinnedMemoryRecord(
                id: item.id,
                text: item.text,
                keywordsData: try encodeArray(item.keywords),
                scopeRawValue: item.scope.rawValue,
                sourceMessageIDsData: try encodeArray(item.sourceMessageIDs),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: record
            )
            context.insert(pinnedMemoryRecord)
            return pinnedMemoryRecord
        }

        record.archiveSegments = try conversation.archiveSegments.enumerated().map { index, item in
            let archiveSegmentRecord = ConversationArchiveSegmentRecord(
                id: item.id,
                title: item.title,
                summary: item.summary,
                keywordsData: try encodeArray(item.keywords),
                openLoopsData: try encodeArray(item.openLoops),
                sourceMessageIDsData: try encodeArray(item.sourceMessageIDs),
                updatedAt: item.updatedAt,
                sortIndex: index,
                conversation: record
            )
            context.insert(archiveSegmentRecord)
            return archiveSegmentRecord
        }
    }

    private func fetchConversationRecord(
        id: UUID,
        in context: ModelContext
    ) throws -> ConversationRecord? {
        var descriptor = FetchDescriptor<ConversationRecord>(
            predicate: #Predicate<ConversationRecord> { record in
                record.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeConversation(from record: ConversationRecord) -> ConversationThread {
        ConversationThread(
            id: record.id,
            title: record.title,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isFavorite: record.isFavorite,
            messages: record.messages
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(makeMessage(from:)),
            aiConfiguration: decodeValue(record.aiConfigurationData),
            focusState: decodeValue(record.focusStateData),
            memoryItems: record.memoryItems
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(makeConversationMemoryItem(from:)),
            pinnedMemories: record.pinnedMemories
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(makeConversationPinnedMemoryItem(from:)),
            archiveSegments: record.archiveSegments
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(makeConversationArchiveSegment(from:))
        )
    }

    private func makeMessage(from record: ConversationMessageRecord) -> ChatMessage {
        ChatMessage(
            id: record.id,
            role: ChatRole(rawValue: record.roleRawValue) ?? .user,
            text: record.text,
            thoughtSummary: record.thoughtSummary?.nonEmptyTrimmed,
            modelResponseParts: decodeValue(record.modelResponsePartsData),
            createdAt: record.createdAt,
            attachments: record.attachments
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(makeAttachment(from:)),
            status: ChatMessageStatus(rawValue: record.statusRawValue) ?? .sent
        )
    }

    private func makeAttachment(from record: ConversationAttachmentRecord) -> ChatAttachment {
        ChatAttachment(
            id: record.id,
            kind: ChatAttachmentKind(rawValue: record.kindRawValue) ?? .image,
            filename: record.filename,
            mimeType: record.mimeType,
            data: record.data,
            blobFilename: record.blobFilename?.nonEmptyTrimmed,
            pixelWidth: record.pixelWidth,
            pixelHeight: record.pixelHeight,
            durationSeconds: record.durationSeconds
        )
    }

    private func makeConversationMemoryItem(
        from record: ConversationMemoryRecord
    ) -> ConversationMemoryItem {
        ConversationMemoryItem(
            id: record.id,
            text: record.text,
            keywords: decodeArray(record.keywordsData),
            sourceMessageIDs: decodeArray(record.sourceMessageIDsData),
            updatedAt: record.updatedAt
        )
    }

    private func makeConversationPinnedMemoryItem(
        from record: ConversationPinnedMemoryRecord
    ) -> PinnedMemoryItem {
        PinnedMemoryItem(
            id: record.id,
            text: record.text,
            keywords: decodeArray(record.keywordsData),
            scope: PinnedMemoryScope(rawValue: record.scopeRawValue) ?? .conversation,
            sourceMessageIDs: decodeArray(record.sourceMessageIDsData),
            updatedAt: record.updatedAt
        )
    }

    private func makeConversationArchiveSegment(
        from record: ConversationArchiveSegmentRecord
    ) -> ConversationArchiveSegment {
        ConversationArchiveSegment(
            id: record.id,
            title: record.title,
            summary: record.summary,
            keywords: decodeArray(record.keywordsData),
            openLoops: decodeArray(record.openLoopsData),
            sourceMessageIDs: decodeArray(record.sourceMessageIDsData),
            updatedAt: record.updatedAt
        )
    }

    private func makePinnedMemoryItem(from record: GlobalPinnedMemoryRecord) -> PinnedMemoryItem {
        PinnedMemoryItem(
            id: record.id,
            text: record.text,
            keywords: decodeArray(record.keywordsData),
            scope: PinnedMemoryScope(rawValue: record.scopeRawValue) ?? .global,
            sourceMessageIDs: decodeArray(record.sourceMessageIDsData),
            updatedAt: record.updatedAt
        )
    }

    private func makeGlobalPinnedMemoryRecord(from item: PinnedMemoryItem) throws -> GlobalPinnedMemoryRecord {
        GlobalPinnedMemoryRecord(
            id: item.id,
            text: item.text,
            keywordsData: try encodeArray(item.keywords),
            scopeRawValue: item.scope.rawValue,
            sourceMessageIDsData: try encodeArray(item.sourceMessageIDs),
            updatedAt: item.updatedAt
        )
    }

    private func makePromptPreset(from record: PromptPresetRecord) -> PromptPreset {
        PromptPreset(
            id: record.id,
            kind: PromptPresetKind(rawValue: record.kindRawValue) ?? .conversation,
            title: record.title,
            content: record.content,
            isBuiltIn: record.isBuiltIn,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func makePromptPresetRecord(from item: PromptPreset) -> PromptPresetRecord {
        PromptPresetRecord(
            id: item.id,
            kindRawValue: item.kind.rawValue,
            title: item.title,
            content: item.content,
            isBuiltIn: item.isBuiltIn,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt
        )
    }

    private func preparedConversationForStorage(_ conversation: ConversationThread) -> ConversationThread {
        var preparedConversation = conversation

        for messageIndex in preparedConversation.messages.indices {
            for attachmentIndex in preparedConversation.messages[messageIndex].attachments.indices {
                let attachment = preparedConversation.messages[messageIndex].attachments[attachmentIndex]
                if attachment.data.isEmpty == false {
                    preparedConversation.messages[messageIndex].attachments[attachmentIndex].blobFilename =
                        attachment.blobFilename?.nonEmptyTrimmed ?? blobFilename(for: attachment)
                } else {
                    preparedConversation.messages[messageIndex].attachments[attachmentIndex].blobFilename =
                        attachment.blobFilename?.nonEmptyTrimmed
                }
            }
        }

        return preparedConversation
    }

    private func ensureDirectoryExists() throws {
        if fileManager.fileExists(atPath: rootURL.path) == false {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: attachmentsRootURL.path) == false {
            try fileManager.createDirectory(at: attachmentsRootURL, withIntermediateDirectories: true)
        }
    }

    private func materializeAttachmentExports(for record: ConversationRecord) throws {
        try materializeAttachmentExports(for: [record])
    }

    private func materializeAttachmentExports(for records: [ConversationRecord]) throws {
        try ensureDirectoryExists()

        for record in records {
            for message in record.messages {
                for attachment in message.attachments {
                    guard attachment.data.isEmpty == false,
                          let blobFilename = attachment.blobFilename?.nonEmptyTrimmed
                    else {
                        continue
                    }

                    let url = attachmentsRootURL.appendingPathComponent(blobFilename, isDirectory: false)
                    try attachment.data.write(to: url, options: [.atomic])
                }
            }
        }
    }

    private func removeOrphanedExportBlobs(
        _ candidateBlobFilenames: Set<String>,
        in context: ModelContext
    ) throws {
        guard candidateBlobFilenames.isEmpty == false else {
            return
        }

        let referencedBlobFilenames = Set(
            try context.fetch(FetchDescriptor<ConversationAttachmentRecord>())
                .compactMap { $0.blobFilename?.nonEmptyTrimmed }
        )

        for blobFilename in candidateBlobFilenames.subtracting(referencedBlobFilenames) {
            let url = attachmentsRootURL.appendingPathComponent(blobFilename, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            try fileManager.removeItem(at: url)
        }
    }

    private func blobFilename(for attachment: ChatAttachment) -> String {
        let sanitizedStem = URL(fileURLWithPath: attachment.filename)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            .nonEmptyTrimmed ?? attachment.kind.rawValue
        let fileExtension = URL(fileURLWithPath: attachment.filename)
            .pathExtension
            .nonEmptyTrimmed ??
            defaultExtension(for: attachment)

        return "\(attachment.id.uuidString)-\(sanitizedStem).\(fileExtension)"
    }

    private func defaultExtension(for attachment: ChatAttachment) -> String {
        switch attachment.kind {
        case .image:
            return "jpg"
        case .audio:
            switch attachment.mimeType.lowercased() {
            case "audio/aac":
                return "aac"
            case "audio/flac":
                return "flac"
            case "audio/mp4", "audio/m4a", "audio/x-m4a":
                return "m4a"
            default:
                return "wav"
            }
        }
    }

    private func encodeValue<T: Encodable>(_ value: T?) throws -> Data? {
        guard let value else {
            return nil
        }

        return try encoder.encode(value)
    }

    private func encodeArray<T: Encodable>(_ items: [T]) throws -> Data {
        try encoder.encode(items)
    }

    private func decodeValue<T: Decodable>(_ data: Data?) -> T? {
        guard let data else {
            return nil
        }

        return try? decoder.decode(T.self, from: data)
    }

    private func decodeArray<T: Decodable>(_ data: Data) -> [T] {
        (try? decoder.decode([T].self, from: data)) ?? []
    }

    private func globalPinnedMemoriesURL() -> URL {
        rootURL.appendingPathComponent("_global_pinned_memories.json", isDirectory: false)
    }

    private func promptPresetsURL() -> URL {
        rootURL.appendingPathComponent("_prompt_presets.json", isDirectory: false)
    }

    private func deletedConversationTombstonesURL() -> URL {
        rootURL.appendingPathComponent("_deleted_conversation_tombstones.json", isDirectory: false)
    }

    private static func sortedPinnedMemories(_ items: [PinnedMemoryItem]) -> [PinnedMemoryItem] {
        items.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func defaultRootURL(
        fileManager: FileManager,
        appGroupIdentifier: String?,
        overrideRootURL: URL?
    ) -> (url: URL, description: String) {
        if let overrideRootURL {
            return (overrideRootURL, L10n.tr("storage.custom"))
        }

        if let appGroupIdentifier,
           let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return (
                appGroupURL.appendingPathComponent("AIChatStore", isDirectory: true),
                L10n.tr("storage.app_group")
            )
        }

        let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        if let baseURL {
            return (
                baseURL.appendingPathComponent("AIChatStore", isDirectory: true),
                localStorageDescription
            )
        }

        return (
            fileManager.temporaryDirectory.appendingPathComponent("AIChatStore", isDirectory: true),
            L10n.tr("storage.temporary_fallback")
        )
    }

    private static var localStorageDescription: String {
        #if os(watchOS)
        return L10n.tr("storage.local.watch")
        #else
        return L10n.tr("storage.local.iphone")
        #endif
    }
}

nonisolated private extension ConversationRecord {
    var allAttachmentBlobFilenames: [String] {
        messages.flatMap { message in
            message.attachments.compactMap { attachment in
                attachment.blobFilename?.nonEmptyTrimmed
            }
        }
    }
}
