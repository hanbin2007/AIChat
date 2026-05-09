//
//  MemoryService.swift
//  AIChat Watch App
//
//  Thin facade over the existing memory-maintenance pipeline
//  (`AIMemoryMaintenanceService`). Owns the heuristic + relay-backed
//  service and exposes a single entry point to ViewModels for "refresh
//  the focus state / memory items / archive segments for this
//  conversation".
//
//  Persistence of the resulting artifacts lives in
//  `ConversationPersistence` — this service only computes them.
//

import Foundation

actor MemoryService {
    private let maintenance: AIMemoryMaintenanceService

    init(maintenance: AIMemoryMaintenanceService) {
        self.maintenance = maintenance
    }

    /// Computes fresh memory artifacts for a conversation. Returns the
    /// new artifacts; caller is responsible for merging them back into
    /// `ConversationThread.focusState/memoryItems/archiveSegments`
    /// and persisting via `ConversationPersistence.upsert`.
    func refreshArtifacts(for conversation: ConversationThread) async -> ConversationMemoryArtifacts {
        await maintenance.refreshArtifacts(for: conversation)
    }
}
