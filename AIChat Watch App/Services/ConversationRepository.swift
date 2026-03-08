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
        .filter { $0.pathExtension == "json" }

        let conversations = try fileURLs.map { url -> ConversationThread in
            let data = try Data(contentsOf: url)
            return try decoder.decode(ConversationThread.self, from: data)
        }

        return conversations.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func save(_ conversation: ConversationThread) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL(for: conversation.id), options: [.atomic])
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
    }

    private static func defaultRootURL(
        fileManager: FileManager,
        appGroupIdentifier: String?,
        overrideRootURL: URL?
    ) -> (url: URL, description: String) {
        if let overrideRootURL {
            return (overrideRootURL, "Custom storage")
        }

        if let appGroupIdentifier,
           let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return (
                appGroupURL.appendingPathComponent("AIChatStore", isDirectory: true),
                "App Group storage"
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
                "Local watch storage"
            )
        }

        return (
            fileManager.temporaryDirectory.appendingPathComponent("AIChatStore", isDirectory: true),
            "Temporary storage fallback"
        )
    }
}
