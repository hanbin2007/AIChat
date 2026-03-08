//
//  ActivationRepository.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation

actor ActivationRepository {
    private let storageKey = "offline_activation_state_v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadState() -> OfflineActivationState? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? decoder.decode(OfflineActivationState.self, from: data)
    }

    func saveState(_ state: OfflineActivationState) throws {
        let data = try encoder.encode(state)
        defaults.set(data, forKey: storageKey)
    }

    func clearState() {
        defaults.removeObject(forKey: storageKey)
    }
}
