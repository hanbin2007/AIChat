//
//  FavoritesViewModel.swift
//  AIChat Watch App
//
//  Filtered projection of the conversation list. Owns its own
//  subscription instead of deriving from `ConversationListViewModel`
//  so it stays a standalone MVVM unit (no inter-ViewModel deps).
//

import Foundation
import Observation

@Observable
@MainActor
final class FavoritesViewModel {
    private(set) var items: [ConversationThread] = []
    private(set) var isLoaded: Bool = false

    private let persistence: ConversationPersistence
    /// Sendable box around the subscription Task. `let` avoids any
    /// isolation pinning so the nonisolated `deinit` can cancel it.
    private let subscription = TaskHandle()

    init(persistence: ConversationPersistence) {
        self.persistence = persistence
    }

    deinit {
        subscription.cancel()
    }

    func start() {
        guard subscription.task == nil else { return }
        subscription.task = Task { [weak self] in
            guard let self else { return }
            let stream = await self.persistence.stream()
            for await snapshot in stream {
                if Task.isCancelled { break }
                let favorites = snapshot.filter { $0.isFavorite }
                await MainActor.run {
                    self.items = favorites
                    self.isLoaded = true
                }
            }
        }
    }

    func unfavorite(id: UUID) async {
        try? await persistence.setFavorite(id: id, isFavorite: false)
    }
}
