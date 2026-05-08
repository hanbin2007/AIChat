//
//  ConversationSettingsViewModel.swift
//  AIChat Watch App
//
//  Drives the per-conversation configuration sheet (title + AI
//  configuration). Persists changes through `ConversationPersistence`.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConversationSettingsViewModel {
    private(set) var conversation: ConversationThread

    private let persistence: ConversationPersistence

    init(conversation: ConversationThread, persistence: ConversationPersistence) {
        self.conversation = conversation
        self.persistence = persistence
    }

    func setTitle(_ title: String) async {
        var updated = conversation
        updated.title = title.nonEmptyTrimmed ?? ConversationThread.untitledTitle
        updated.updatedAt = Date()
        do {
            updated = try await persistence.upsert(updated)
            conversation = updated
        } catch {
            // Keep the in-memory edit but surface failure to the
            // caller via a future error channel; UI is still pure
            // placeholder so don't crash the screen.
        }
    }

    func setAIConfiguration(_ configuration: ConversationAIConfiguration) async {
        var updated = conversation
        updated.aiConfiguration = configuration
        updated.updatedAt = Date()
        do {
            updated = try await persistence.upsert(updated)
            conversation = updated
        } catch {
            // Same as above.
        }
    }
}
