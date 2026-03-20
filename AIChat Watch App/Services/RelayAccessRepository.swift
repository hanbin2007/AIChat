import Foundation

nonisolated struct RelayAccessState: Codable, Equatable, Sendable {
    var status: RelayAccountStatusResponse?
    var updatedAt: Date
}

actor RelayAccessRepository {
    private static let storageKey = "relay_access_state_v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadState() -> RelayAccessState? {
        Self.storedState(defaults: defaults)
    }

    func saveStatus(_ status: RelayAccountStatusResponse) throws {
        let nextState = RelayAccessState(status: status, updatedAt: .now)
        let data = try encoder.encode(nextState)
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    nonisolated static func makeDefaults(appGroupIdentifier: String?) -> UserDefaults {
        if let appGroupIdentifier,
           let defaults = UserDefaults(suiteName: appGroupIdentifier) {
            return defaults
        }

        return .standard
    }

    nonisolated static func storedState(appGroupIdentifier: String?) -> RelayAccessState? {
        storedState(defaults: makeDefaults(appGroupIdentifier: appGroupIdentifier))
    }

    nonisolated static func storedRelayKey(appGroupIdentifier: String?) -> String? {
        storedState(appGroupIdentifier: appGroupIdentifier)?
            .status?
            .key?
            .keyValue
            .nonEmptyTrimmed
    }

    private nonisolated static func storedState(defaults: UserDefaults) -> RelayAccessState? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RelayAccessState.self, from: data)
    }
}
