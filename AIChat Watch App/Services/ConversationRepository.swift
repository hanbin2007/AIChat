//
//  ConversationRepository.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

actor ConversationRepository {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)

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

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseURL ?? fileManager.temporaryDirectory)
            .appendingPathComponent("AIChatStore", isDirectory: true)
    }
}
