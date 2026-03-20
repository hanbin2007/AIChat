//
//  ActivationStoreModels.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/20.
//

import Foundation
import SwiftData

@Model
final class ActivationStateRecord {
    @Attribute(.unique) var key: String
    var deviceTokenString: String
    var requestIssuedAt: Date
    var validFrom: Date
    var validUntil: Date?
    var messageLimit: Int?
    var modelMask: Int
    var activationCodeFingerprint: String
    var activatedAt: Date
    var usedMessageCount: Int

    init(
        key: String = "primary",
        deviceTokenString: String,
        requestIssuedAt: Date,
        validFrom: Date,
        validUntil: Date?,
        messageLimit: Int?,
        modelMask: Int,
        activationCodeFingerprint: String,
        activatedAt: Date,
        usedMessageCount: Int
    ) {
        self.key = key
        self.deviceTokenString = deviceTokenString
        self.requestIssuedAt = requestIssuedAt
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.messageLimit = messageLimit
        self.modelMask = modelMask
        self.activationCodeFingerprint = activationCodeFingerprint
        self.activatedAt = activatedAt
        self.usedMessageCount = usedMessageCount
    }
}

@Model
final class CompanionDeviceIdentityRecord {
    @Attribute(.unique) var key: String
    var rawIdentifier: String

    init(key: String = "current", rawIdentifier: String) {
        self.key = key
        self.rawIdentifier = rawIdentifier
    }
}

@Model
final class RelayAccessStateRecord {
    @Attribute(.unique) var key: String
    @Attribute(.externalStorage) var statusData: Data?
    var relayKeyValue: String?
    var updatedAt: Date

    init(
        key: String = "primary",
        statusData: Data? = nil,
        relayKeyValue: String? = nil,
        updatedAt: Date
    ) {
        self.key = key
        self.statusData = statusData
        self.relayKeyValue = relayKeyValue
        self.updatedAt = updatedAt
    }
}

nonisolated enum BillingActivationStoreSupport {
    static let sqliteFilename = "BillingActivationStore.sqlite"
    static let schema = Schema([
        ActivationStateRecord.self,
        CompanionDeviceIdentityRecord.self,
        RelayAccessStateRecord.self
    ])

    static func makeContainer(
        appGroupIdentifier: String?,
        overrideRootURL: URL?,
        fileManager: FileManager
    ) throws -> (rootURL: URL, container: ModelContainer) {
        let rootURL = defaultRootURL(
            fileManager: fileManager,
            appGroupIdentifier: appGroupIdentifier,
            overrideRootURL: overrideRootURL
        )
        if fileManager.fileExists(atPath: rootURL.path) == false {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        let configuration = ModelConfiguration(
            "BillingActivationStore",
            schema: schema,
            url: rootURL.appendingPathComponent(sqliteFilename, isDirectory: false),
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (rootURL, container)
    }

    static func defaultRootURL(
        fileManager: FileManager,
        appGroupIdentifier: String?,
        overrideRootURL: URL?
    ) -> URL {
        if let overrideRootURL {
            return overrideRootURL
        }

        if let appGroupIdentifier,
           let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return appGroupURL.appendingPathComponent("AIChatStore", isDirectory: true)
        }

        let localScopeName = localStoreScopeName()
        let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        if let baseURL {
            return baseURL
                .appendingPathComponent("AIChatStore", isDirectory: true)
                .appendingPathComponent(localScopeName, isDirectory: true)
        }

        return fileManager.temporaryDirectory
            .appendingPathComponent("AIChatStore", isDirectory: true)
            .appendingPathComponent(localScopeName, isDirectory: true)
    }

    private static func localStoreScopeName(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> String {
        if let bundleIdentifier = bundle.bundleIdentifier?.nonEmptyTrimmed {
            return bundleIdentifier
        }

        return processInfo.processName
            .replacingOccurrences(of: "/", with: "-")
            .nonEmptyTrimmed ?? "AIChat"
    }
}
