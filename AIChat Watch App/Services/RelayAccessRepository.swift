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

/// Process-wide cache backing `RelayAccessRepository.storedRelayKey` /
/// `storedState`. Both used to open a fresh SwiftData `ModelContainer` and run
/// a SQLite fetch on EVERY call — and `resolvedRelayBearerToken` calls them on
/// every SwiftUI body eval, on the main actor. This caches:
///   - the `ModelContainer` per resolved root URL (containers are expensive to
///     open and safe to share), and
///   - the last resolved relay key per app-group identifier,
/// invalidated whenever the status is saved or cleared.
private final class RelayAccessStoreCache: @unchecked Sendable {
    static let shared = RelayAccessStoreCache()

    private let lock = NSLock()
    private var containersByPath: [String: ModelContainer] = [:]
    private var resolvedKeyByGroup: [String: String?] = [:]

    private func cacheGroupKey(_ appGroupIdentifier: String?) -> String {
        appGroupIdentifier ?? "<local>"
    }

    func container(
        for rootURL: URL,
        make: () throws -> ModelContainer
    ) throws -> ModelContainer {
        lock.lock()
        defer { lock.unlock() }

        let path = rootURL.path
        if let existing = containersByPath[path] {
            return existing
        }

        let container = try make()
        containersByPath[path] = container
        return container
    }

    func cachedResolvedKey(for appGroupIdentifier: String?) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedKeyByGroup[cacheGroupKey(appGroupIdentifier)]
    }

    func storeResolvedKey(_ key: String?, for appGroupIdentifier: String?) {
        lock.lock()
        defer { lock.unlock() }
        resolvedKeyByGroup[cacheGroupKey(appGroupIdentifier)] = key
    }

    func invalidateResolvedKey(for appGroupIdentifier: String?) {
        lock.lock()
        defer { lock.unlock() }
        resolvedKeyByGroup.removeValue(forKey: cacheGroupKey(appGroupIdentifier))
    }
}

actor RelayAccessRepository {
    private static let storageKey = "primary"

    private let modelContainer: ModelContainer?
    private let initializationError: Error?
    private let appGroupIdentifier: String?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: AppConfiguration? = nil,
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.applyRelayDateDecoding()
        self.appGroupIdentifier = configuration?.appGroupIdentifier

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
        record.relayKeyValue = status.key?.keyValue.nonEmptyTrimmed
        record.updatedAt = .now
        try context.save()
        // The persisted key just changed — drop the cached resolution so the
        // next `resolvedRelayBearerToken` re-reads it.
        RelayAccessStoreCache.shared.invalidateResolvedKey(for: appGroupIdentifier)
    }

    func clear() throws {
        let context = try makeContext()
        if let record = try fetchRelayAccessStateRecord(in: context) {
            context.delete(record)
            try context.save()
        }
        RelayAccessStoreCache.shared.invalidateResolvedKey(for: appGroupIdentifier)
    }

    /// Clears only the stored relay key (used when the relay returns 401 for a
    /// revoked/expired key) while leaving the rest of the cached status intact.
    /// Falls back to a full `clear()` when no record exists.
    func clearStoredKey() throws {
        let context = try makeContext()
        guard let record = try fetchRelayAccessStateRecord(in: context) else {
            RelayAccessStoreCache.shared.invalidateResolvedKey(for: appGroupIdentifier)
            return
        }

        if var status = try record.statusData.map({ try decoder.decode(RelayAccountStatusResponse.self, from: $0) }) {
            status.key = nil
            record.statusData = try encoder.encode(status)
        }
        record.relayKeyValue = nil
        record.updatedAt = .now
        try context.save()
        RelayAccessStoreCache.shared.invalidateResolvedKey(for: appGroupIdentifier)
    }

    nonisolated static func storedState(appGroupIdentifier: String?) -> RelayAccessState? {
        do {
            // Resolve the root URL cheaply (no container open) so a warm cache
            // skips opening a fresh SQLite handle entirely.
            let rootURL = BillingActivationStoreSupport.defaultRootURL(
                fileManager: .default,
                appGroupIdentifier: appGroupIdentifier,
                overrideRootURL: nil
            )
            let container = try RelayAccessStoreCache.shared.container(for: rootURL) {
                try BillingActivationStoreSupport.makeContainer(
                    appGroupIdentifier: appGroupIdentifier,
                    overrideRootURL: nil,
                    fileManager: .default
                ).container
            }
            let context = ModelContext(container)
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
            decoder.applyRelayDateDecoding()
            let status = try record.statusData.map { try decoder.decode(RelayAccountStatusResponse.self, from: $0) }
            return RelayAccessState(status: status, updatedAt: record.updatedAt)
        } catch {
            return nil
        }
    }

    nonisolated static func storedRelayKey(appGroupIdentifier: String?) -> String? {
        // Hot path: invoked from `resolvedRelayBearerToken` on every SwiftUI
        // body eval. Serve from the in-memory cache when warm; only touch
        // SQLite on a cold cache (or after an explicit invalidation).
        if let cached = RelayAccessStoreCache.shared.cachedResolvedKey(for: appGroupIdentifier) {
            return cached
        }

        let resolved = storedState(appGroupIdentifier: appGroupIdentifier)?
            .status?
            .key?
            .keyValue
            .nonEmptyTrimmed
        RelayAccessStoreCache.shared.storeResolvedKey(resolved, for: appGroupIdentifier)
        return resolved
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
