import Foundation
import SwiftData

nonisolated struct RelayAccessState: Codable, Equatable, Sendable {
    var status: RelayAccountStatusResponse?
    var updatedAt: Date
}

private enum RelayAccessRepositoryError: LocalizedError {
    case storageInitializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .storageInitializationFailed(let reason):
            return "Failed to initialize relay access store: \(reason)"
        }
    }
}

actor RelayAccessRepository {
    private static let storageKey = "primary"

    private let modelContainer: ModelContainer?
    private let initializationError: Error?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601

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
            self.initializationError = RelayAccessRepositoryError.storageInitializationFailed(
                error.localizedDescription
            )
        }
    }

    func loadState() -> RelayAccessState? {
        do {
            guard let record = try fetchRelayAccessStateRecord(in: makeContext()) else {
                return nil
            }

            return try makeRelayAccessState(from: record)
        } catch {
            return nil
        }
    }

    func saveStatus(_ status: RelayAccountStatusResponse) throws {
        let context = try makeContext()
        let record = try fetchRelayAccessStateRecord(in: context) ??
            RelayAccessStateRecord(key: Self.storageKey, updatedAt: .now)
        if record.modelContext == nil {
            context.insert(record)
        }

        record.statusData = try encoder.encode(status)
        record.relayKeyValue = status.key?.keyValue?.nonEmptyTrimmed
        record.updatedAt = .now
        try context.save()
    }

    func clear() throws {
        let context = try makeContext()
        if let record = try fetchRelayAccessStateRecord(in: context) {
            context.delete(record)
            try context.save()
        }
    }

    nonisolated static func storedState(appGroupIdentifier: String?) -> RelayAccessState? {
        do {
            let store = try BillingActivationStoreSupport.makeContainer(
                appGroupIdentifier: appGroupIdentifier,
                overrideRootURL: nil,
                fileManager: .default
            )
            let context = ModelContext(store.container)
            let storageKey = Self.storageKey
            var descriptor = FetchDescriptor<RelayAccessStateRecord>(
                predicate: #Predicate<RelayAccessStateRecord> { record in
                    record.key == storageKey
                }
            )
            descriptor.fetchLimit = 1
            guard let record = try context.fetch(descriptor).first else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let status = try record.statusData.map { try decoder.decode(RelayAccountStatusResponse.self, from: $0) }
            return RelayAccessState(status: status, updatedAt: record.updatedAt)
        } catch {
            return nil
        }
    }

    nonisolated static func storedRelayKey(appGroupIdentifier: String?) -> String? {
        storedState(appGroupIdentifier: appGroupIdentifier)?
            .status?
            .key?
            .keyValue?
            .nonEmptyTrimmed
    }

    private func makeContext() throws -> ModelContext {
        if let initializationError {
            throw initializationError
        }

        guard let modelContainer else {
            throw RelayAccessRepositoryError.storageInitializationFailed(
                "Missing billing activation container."
            )
        }

        return ModelContext(modelContainer)
    }

    private func fetchRelayAccessStateRecord(in context: ModelContext) throws -> RelayAccessStateRecord? {
        let storageKey = Self.storageKey
        var descriptor = FetchDescriptor<RelayAccessStateRecord>(
            predicate: #Predicate<RelayAccessStateRecord> { record in
                record.key == storageKey
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeRelayAccessState(from record: RelayAccessStateRecord) throws -> RelayAccessState {
        let status = try record.statusData.map { try decoder.decode(RelayAccountStatusResponse.self, from: $0) }
        return RelayAccessState(status: status, updatedAt: record.updatedAt)
    }
}
