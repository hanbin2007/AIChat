//
//  GlobalPinnedMemoryViewModel.swift
//  AIChat Watch App
//
//  Drives the global pinned memory editor. Wraps
//  `ConversationPersistence.loadGlobalPinnedMemories()` /
//  `saveGlobalPinnedMemories(_:)` with full CRUD so the view can add,
//  edit, and remove items individually. The persistence layer expects
//  the full list on every save, so we keep the canonical list in
//  `items` and replay it on every mutation.
//

import Foundation
import Observation

@Observable
@MainActor
final class GlobalPinnedMemoryViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var items: [PinnedMemoryItem] = []
    private(set) var loadState: LoadState = .idle

    private let persistence: ConversationPersistence

    init(persistence: ConversationPersistence) {
        self.persistence = persistence
    }

    func refresh() async {
        loadState = .loading
        do {
            items = try await persistence.loadGlobalPinnedMemories()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func add(text: String, keywords: [String] = []) async {
        let item = PinnedMemoryItem(text: text, keywords: keywords, scope: .global)
        guard !item.text.isEmpty else { return }
        let next = items + [item]
        await save(next)
    }

    func update(_ item: PinnedMemoryItem) async {
        var next = items
        guard let index = next.firstIndex(where: { $0.id == item.id }) else { return }
        next[index] = item
        await save(next)
    }

    func remove(id: UUID) async {
        let next = items.filter { $0.id != id }
        await save(next)
    }

    private func save(_ next: [PinnedMemoryItem]) async {
        do {
            try await persistence.saveGlobalPinnedMemories(next)
            items = next
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
