//
//  ActivationRepository.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import SwiftData

private enum ActivationRepositoryError: LocalizedError {
    case storageInitializationFailed(String)
    case corruptedActivationState

    var errorDescription: String? {
        switch self {
        case .storageInitializationFailed(let reason):
            return "Failed to initialize activation store: \(reason)"
        case .corruptedActivationState:
            return "The activation state in storage is invalid."
        }
    }
}

nonisolated final class ActivationRepository {
    private static let activationStateKey = "primary"
    private static let deviceIdentityKey = "current"

    private let modelContainer: ModelContainer?
    private let initializationError: Error?

    init(
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        do {
            let store = try BillingActivationStoreSupport.makeContainer(
                appGroupIdentifier: configuration?.appGroupIdentifier,
                overrideRootURL: rootURL,
                fileManager: fileManager
            )
            self.modelContainer = store.container
            self.initializationError = nil
        } catch {
            self.modelContainer = nil
            self.initializationError = ActivationRepositoryError.storageInitializationFailed(
                error.localizedDescription
            )
        }
    }

    func loadState() -> OfflineActivationState? {
        do {
            guard let record = try fetchActivationStateRecord(in: makeContext()) else {
                return nil
            }

            return try makeOfflineActivationState(from: record)
        } catch {
            return nil
        }
    }

    func saveState(_ state: OfflineActivationState) throws {
        let context = try makeContext()
        let record = try fetchActivationStateRecord(in: context) ?? ActivationStateRecord(
            key: Self.activationStateKey,
            deviceTokenString: String(state.license.deviceToken),
            requestIssuedAt: state.license.requestIssuedAt,
            validFrom: state.license.validFrom,
            validUntil: state.license.validUntil,
            messageLimit: state.license.messageLimit,
            modelMask: Int(state.license.modelMask),
            activationCodeFingerprint: state.activationCodeFingerprint,
            activatedAt: state.activatedAt,
            usedMessageCount: state.usedMessageCount
        )
        if record.modelContext == nil {
            context.insert(record)
        }

        record.deviceTokenString = String(state.license.deviceToken)
        record.requestIssuedAt = state.license.requestIssuedAt
        record.validFrom = state.license.validFrom
        record.validUntil = state.license.validUntil
        record.messageLimit = state.license.messageLimit
        record.modelMask = Int(state.license.modelMask)
        record.activationCodeFingerprint = state.activationCodeFingerprint
        record.activatedAt = state.activatedAt
        record.usedMessageCount = state.usedMessageCount
        try context.save()
    }

    func clearState() throws {
        let context = try makeContext()
        if let record = try fetchActivationStateRecord(in: context) {
            context.delete(record)
            try context.save()
        }
    }

    func loadOrCreateFallbackIdentifier() -> String {
        do {
            let context = try makeContext()
            if let record = try fetchDeviceIdentityRecord(in: context),
               record.rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return record.rawIdentifier
            }

            let rawIdentifier = UUID().uuidString.uppercased()
            let record = try fetchDeviceIdentityRecord(in: context) ??
                CompanionDeviceIdentityRecord(key: Self.deviceIdentityKey, rawIdentifier: rawIdentifier)
            if record.modelContext == nil {
                context.insert(record)
            }

            record.rawIdentifier = rawIdentifier
            try context.save()
            return rawIdentifier
        } catch {
            return UUID().uuidString.uppercased()
        }
    }

    private func makeContext() throws -> ModelContext {
        if let initializationError {
            throw initializationError
        }

        guard let modelContainer else {
            throw ActivationRepositoryError.storageInitializationFailed("Missing model container.")
        }

        return ModelContext(modelContainer)
    }

    private func fetchActivationStateRecord(in context: ModelContext) throws -> ActivationStateRecord? {
        let activationStateKey = Self.activationStateKey
        var descriptor = FetchDescriptor<ActivationStateRecord>(
            predicate: #Predicate<ActivationStateRecord> { record in
                record.key == activationStateKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchDeviceIdentityRecord(in context: ModelContext) throws -> CompanionDeviceIdentityRecord? {
        let deviceIdentityKey = Self.deviceIdentityKey
        var descriptor = FetchDescriptor<CompanionDeviceIdentityRecord>(
            predicate: #Predicate<CompanionDeviceIdentityRecord> { record in
                record.key == deviceIdentityKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeOfflineActivationState(
        from record: ActivationStateRecord
    ) throws -> OfflineActivationState {
        guard let deviceToken = UInt64(record.deviceTokenString),
              let modelMask = UInt16(exactly: record.modelMask)
        else {
            throw ActivationRepositoryError.corruptedActivationState
        }

        return OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: deviceToken,
                requestIssuedAt: record.requestIssuedAt,
                validFrom: record.validFrom,
                validUntil: record.validUntil,
                messageLimit: record.messageLimit,
                modelMask: modelMask
            ),
            activationCodeFingerprint: record.activationCodeFingerprint,
            activatedAt: record.activatedAt,
            usedMessageCount: record.usedMessageCount
        )
    }
}
