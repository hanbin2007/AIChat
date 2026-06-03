//
//  RelayMemoryExtractor.swift
//  AIChat Watch App
//
//  Adapter that turns `RelayAPIClient.extractMemory` into the shape
//  the existing `ModelBackedMemoryMaintenanceService` consumes
//  (`AIMemoryExtractionClient`). Replaces the legacy
//  `MemoryExtractionClients.swift::RelayMemoryExtractionClient`,
//  which talked to the old relay over its own URLSession + URL
//  formatter.
//

import Foundation

struct RelayMemoryExtractor: AIMemoryExtractionClient {
    let api: RelayAPIClient

    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse {
        let payload = RelayMemoryExtractRequest(
            model: request.model,
            mode: request.mode,
            conversationTitle: request.conversationTitle,
            existingFocusState: request.existingFocusState.map { focus in
                RelayMemoryFocusState(
                    kind: focus.kind ?? "",
                    title: focus.title,
                    focusNote: focus.focusNote,
                    openLoops: focus.openLoops
                )
            },
            existingMemoryItems: request.existingMemoryItems,
            recentMessages: request.recentMessages.map {
                RelayMemoryMessage(role: $0.role, text: $0.text)
            },
            archiveCandidateMessages: request.archiveCandidateMessages.map {
                RelayMemoryMessage(role: $0.role, text: $0.text)
            }
        )
        let response = try await api.extractMemory(payload)
        return ConversationMemoryExtractionResponse(
            kind: response.kind,
            title: response.title,
            focusNote: response.focusNote,
            openLoops: response.openLoops ?? [],
            memoryItems: response.memoryItems ?? [],
            archiveTitle: response.archiveTitle,
            archiveSummary: response.archiveSummary,
            archiveOpenLoops: response.archiveOpenLoops ?? []
        )
    }
}
