import Foundation

/// JSON-file persistence of EntitlementState with a schema-version guard.
nonisolated struct EntitlementCache {
    static let currentSchemaVersion = 1
    let directory: URL
    var cacheDirectoryURL: URL {
        directory.appendingPathComponent("entitlements", isDirectory: true)
    }
    var fileURL: URL { cacheDirectoryURL.appendingPathComponent("entitlement-state.json") }

    func save(_ state: EntitlementState) throws {
        var s = state
        s.schemaVersion = Self.currentSchemaVersion
        let data = try JSONEncoder().encode(s)
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func load() -> EntitlementState? {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(EntitlementState.self, from: data),
              state.schemaVersion == Self.currentSchemaVersion
        else { return nil }
        return state
    }

    func markRelayKeyRevoked() throws {
        guard var state = load() else {
            return
        }

        state.lastError = .revoked
        try save(state)
    }

    func clear() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
