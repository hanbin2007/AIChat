//
//  ConversationListViewModel.swift
//  AIChat Watch App
//
//  Drives the main conversation list. Subscribes once to
//  `ConversationPersistence.stream()` and re-binds `items` on each
//  emission. Mutations (`createNew` / `delete` / `toggleFavorite`)
//  delegate to the persistence actor; the stream callback is what
//  actually updates the published list.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConversationListViewModel {
    enum LoadState: Equatable {
        case idle
        case loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var items: [ConversationThread] = []

    private let persistence: ConversationPersistence
    /// Marked nonisolated(unsafe) so `deinit` (which is itself
    /// nonisolated in Swift 6) can cancel the subscription. The Task
    /// is the only writer outside `init` / `start` so this is safe.
    nonisolated(unsafe) private var subscription: Task<Void, Never>?

    init(persistence: ConversationPersistence) {
        self.persistence = persistence
    }

    deinit {
        subscription?.cancel()
    }

    /// Starts subscribing to the persistence stream. Idempotent —
    /// calling twice is a no-op.
    func start() {
        guard subscription == nil else { return }
        subscription = Task { [weak self] in
            guard let self else { return }
            let stream = await self.persistence.stream()
            for await snapshot in stream {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.items = snapshot
                    self.loadState = .loaded
                }
            }
        }
    }

    /// Inserts a fresh conversation row and persists it. Returns the
    /// new thread id so the caller can navigate to detail.
    @discardableResult
    func createNew(seedTitle: String? = nil) async -> UUID? {
        let thread = ConversationThread(
            title: seedTitle ?? ConversationThread.untitledTitle
        )
        do {
            try await persistence.upsert(thread)
            return thread.id
        } catch {
            loadState = .failed(error.localizedDescription)
            return nil
        }
    }

    func delete(id: UUID) async {
        do {
            try await persistence.delete(id: id)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggleFavorite(id: UUID) async {
        guard let current = items.first(where: { $0.id == id }) else { return }
        do {
            try await persistence.setFavorite(id: id, isFavorite: !current.isFavorite)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
