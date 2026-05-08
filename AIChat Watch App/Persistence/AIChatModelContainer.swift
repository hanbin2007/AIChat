//
//  AIChatModelContainer.swift
//  AIChat Watch App
//
//  Container builder for the V2 SwiftData store. Resolves the storage
//  URL the same way V1 does (App Group → Application Support →
//  temp dir) so a future side-by-side launch can read both stores
//  without diverging path logic.
//
//  Tests use `inMemory()` which spins up a `:memory:` container with
//  no on-disk side effects.
//

import Foundation
import SwiftData

enum AIChatModelContainerError: Error, LocalizedError {
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Failed to initialize AIChat V2 store: \(message)"
        }
    }
}

enum AIChatModelContainer {
    /// V2 sqlite filename — distinct from V1's `ConversationStore.sqlite`
    /// so both stores coexist during the migration window.
    static let sqliteFilename = "AIChatStoreV2.sqlite"

    /// Disk-backed container at the app's preferred storage root.
    static func makeOnDisk(
        appGroupIdentifier: String? = nil,
        overrideRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let rootURL = resolvedRootURL(
            appGroupIdentifier: appGroupIdentifier,
            overrideRootURL: overrideRootURL,
            fileManager: fileManager
        )

        do {
            if fileManager.fileExists(atPath: rootURL.path) == false {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            }
            let configuration = ModelConfiguration(
                "AIChatStoreV2",
                schema: AIChatSchemaV2.makeSchema(),
                url: rootURL.appendingPathComponent(sqliteFilename, isDirectory: false),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: AIChatSchemaV2.makeSchema(),
                configurations: [configuration]
            )
        } catch {
            throw AIChatModelContainerError.initializationFailed(error.localizedDescription)
        }
    }

    /// In-memory container for unit tests.
    static func inMemory() throws -> ModelContainer {
        do {
            let configuration = ModelConfiguration(
                "AIChatStoreV2-InMemory",
                schema: AIChatSchemaV2.makeSchema(),
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: AIChatSchemaV2.makeSchema(),
                configurations: [configuration]
            )
        } catch {
            throw AIChatModelContainerError.initializationFailed(error.localizedDescription)
        }
    }

    private static func resolvedRootURL(
        appGroupIdentifier: String?,
        overrideRootURL: URL?,
        fileManager: FileManager
    ) -> URL {
        if let overrideRootURL { return overrideRootURL }
        if let appGroupIdentifier,
           let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url.appendingPathComponent("AIChatStore", isDirectory: true)
        }
        if let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return baseURL.appendingPathComponent("AIChatStore", isDirectory: true)
        }
        return fileManager.temporaryDirectory.appendingPathComponent("AIChatStore", isDirectory: true)
    }
}
