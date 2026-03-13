//
//  ConversationRepository.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

actor ConversationRepository {
    nonisolated let storageDescription: String
    nonisolated let resolvedRootURL: URL

    private let rootURL: URL
    private let attachmentsRootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

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
        self.storageDescription = resolvedStorage.description

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func loadConversations() throws -> [ConversationThread] {
        try ensureDirectoryExists()

        let fileURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension == "json" &&
            $0.lastPathComponent.hasPrefix("_") == false
        }

        let conversations = try fileURLs.map { url -> ConversationThread in
            let data = try Data(contentsOf: url)
            let conversation = try decoder.decode(ConversationThread.self, from: data)
            return hydrateAttachments(in: conversation)
        }

        return conversations.sorted(by: ConversationThread.sortsByMostRecentFirst)
    }

    func save(_ conversation: ConversationThread) throws {
        try ensureDirectoryExists()
        let persistedConversation = try persistAttachmentBlobs(for: conversation)
        let data = try encoder.encode(persistedConversation)
        try data.write(to: fileURL(for: conversation.id), options: [.atomic])
    }

    func loadGlobalPinnedMemories() throws -> [PinnedMemoryItem] {
        try ensureDirectoryExists()
        let url = globalPinnedMemoriesURL()
        guard fileManager.fileExists(atPath: url.path()) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PinnedMemoryItem].self, from: data)
    }

    func saveGlobalPinnedMemories(_ items: [PinnedMemoryItem]) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(items)
        try data.write(to: globalPinnedMemoriesURL(), options: [.atomic])
    }

    func loadPromptPresets() throws -> [PromptPreset] {
        try ensureDirectoryExists()
        let url = promptPresetsURL()
        guard fileManager.fileExists(atPath: url.path()) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode([PromptPreset].self, from: data)
    }

    func savePromptPresets(_ items: [PromptPreset]) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(items)
        try data.write(to: promptPresetsURL(), options: [.atomic])
    }

    func deleteConversation(id: UUID) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path()) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    private func fileURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        if fileManager.fileExists(atPath: rootURL.path()) == false {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: attachmentsRootURL.path()) == false {
            try fileManager.createDirectory(at: attachmentsRootURL, withIntermediateDirectories: true)
        }
    }

    private func globalPinnedMemoriesURL() -> URL {
        rootURL.appendingPathComponent("_global_pinned_memories.json", isDirectory: false)
    }

    private func promptPresetsURL() -> URL {
        rootURL.appendingPathComponent("_prompt_presets.json", isDirectory: false)
    }

    private func persistAttachmentBlobs(for conversation: ConversationThread) throws -> ConversationThread {
        var persistedConversation = conversation

        for messageIndex in persistedConversation.messages.indices {
            for attachmentIndex in persistedConversation.messages[messageIndex].attachments.indices {
                let attachment = persistedConversation.messages[messageIndex].attachments[attachmentIndex]
                var persistedAttachment = attachment

                if attachment.data.isEmpty == false {
                    let blobFilename = attachment.blobFilename?.nonEmptyTrimmed ?? blobFilename(for: attachment)
                    let blobURL = attachmentsRootURL.appendingPathComponent(blobFilename, isDirectory: false)
                    try attachment.data.write(to: blobURL, options: [.atomic])
                    persistedAttachment.blobFilename = blobFilename
                }

                persistedAttachment.data = Data()
                persistedConversation.messages[messageIndex].attachments[attachmentIndex] = persistedAttachment
            }
        }

        return persistedConversation
    }

    private func hydrateAttachments(in conversation: ConversationThread) -> ConversationThread {
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
            return "wav"
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
