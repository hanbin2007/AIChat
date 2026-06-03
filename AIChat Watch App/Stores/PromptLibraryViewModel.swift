//
//  PromptLibraryViewModel.swift
//  AIChat Watch App
//
//  Drives the preset library. CRUD lives in `ConversationPersistence`
//  via the `loadPromptPresets()` / `savePromptPresets(_:)` pair —
//  there's no per-row update endpoint because the table is small (a
//  handful of presets) and a full replace is simpler + atomic.
//

import Foundation
import Observation

@Observable
@MainActor
final class PromptLibraryViewModel {
    private(set) var presets: [PromptPreset] = []
    private(set) var loadError: String?

    private let persistence: ConversationPersistence

    init(persistence: ConversationPersistence) {
        self.persistence = persistence
    }

    func refresh() async {
        do {
            presets = try await persistence.loadPromptPresets()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func upsert(_ preset: PromptPreset) async {
        var updated = presets
        if let index = updated.firstIndex(where: { $0.id == preset.id }) {
            updated[index] = preset
        } else {
            updated.append(preset)
        }
        do {
            try await persistence.savePromptPresets(updated)
            presets = updated
        } catch {
            loadError = error.localizedDescription
        }
    }

    func delete(id: UUID) async {
        let updated = presets.filter { $0.id != id }
        do {
            try await persistence.savePromptPresets(updated)
            presets = updated
        } catch {
            loadError = error.localizedDescription
        }
    }
}
