//
//  AIMemoryMaintenanceService.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/10.
//

import Foundation

nonisolated struct ConversationMemoryArtifacts: Equatable {
    var focusState: ConversationFocusState?
    var memoryItems: [ConversationMemoryItem]
    var archiveSegments: [ConversationArchiveSegment]
}

nonisolated struct ConversationMemoryMessagePayload: Codable, Equatable {
    var id: String
    var role: String
    var text: String
}

nonisolated struct ConversationMemoryFocusPayload: Codable, Equatable {
    var kind: String?
    var title: String?
    var focusNote: String?
    var openLoops: [String]

    init(
        kind: String? = nil,
        title: String? = nil,
        focusNote: String? = nil,
        openLoops: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.focusNote = focusNote
        self.openLoops = openLoops
    }
}

nonisolated struct ConversationMemoryExtractionRequest: Codable, Equatable {
    var model: String
    var mode: String
    var conversationTitle: String
    var recentMessages: [ConversationMemoryMessagePayload]
    var existingFocusState: ConversationMemoryFocusPayload?
    var existingMemoryItems: [String]
    var archiveCandidateMessages: [ConversationMemoryMessagePayload]
}

nonisolated struct ConversationMemoryExtractionResponse: Codable, Equatable {
    var kind: String?
    var title: String?
    var focusNote: String?
    var openLoops: [String]
    var memoryItems: [String]
    var archiveTitle: String?
    var archiveSummary: String?
    var archiveOpenLoops: [String]

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case focusNote
        case openLoops
        case memoryItems
        case archiveTitle
        case archiveSummary
        case archiveOpenLoops
    }

    init(
        kind: String? = nil,
        title: String? = nil,
        focusNote: String? = nil,
        openLoops: [String] = [],
        memoryItems: [String] = [],
        archiveTitle: String? = nil,
        archiveSummary: String? = nil,
        archiveOpenLoops: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.focusNote = focusNote
        self.openLoops = openLoops
        self.memoryItems = memoryItems
        self.archiveTitle = archiveTitle
        self.archiveSummary = archiveSummary
        self.archiveOpenLoops = archiveOpenLoops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.focusNote = try container.decodeIfPresent(String.self, forKey: .focusNote)
        self.openLoops = try container.decodeIfPresent([String].self, forKey: .openLoops) ?? []
        self.memoryItems = try container.decodeIfPresent([String].self, forKey: .memoryItems) ?? []
        self.archiveTitle = try container.decodeIfPresent(String.self, forKey: .archiveTitle)
        self.archiveSummary = try container.decodeIfPresent(String.self, forKey: .archiveSummary)
        self.archiveOpenLoops = try container.decodeIfPresent([String].self, forKey: .archiveOpenLoops) ?? []
    }
}

protocol AIMemoryMaintenanceService {
    func refreshArtifacts(for conversation: ConversationThread) async -> ConversationMemoryArtifacts
}

protocol AIMemoryExtractionClient {
    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse
}

nonisolated struct HeuristicMemoryMaintenanceService: AIMemoryMaintenanceService {
    func refreshArtifacts(for conversation: ConversationThread) async -> ConversationMemoryArtifacts {
        refreshArtifactsSynchronously(for: conversation)
    }

    func refreshArtifactsSynchronously(for conversation: ConversationThread) -> ConversationMemoryArtifacts {
        let visibleMessages = contextEligibleMessages(in: conversation)
        let mode = AIContextAssembler.detectedMode(for: conversation)

        return ConversationMemoryArtifacts(
            focusState: deriveFocusState(
                from: visibleMessages,
                existingFocusState: conversation.focusState,
                mode: mode,
                conversationTitle: conversation.title
            ),
            memoryItems: deriveMemoryItems(from: visibleMessages),
            archiveSegments: deriveArchiveSegments(
                from: visibleMessages,
                existingSegments: conversation.archiveSegments,
                protectedRecentMessages: 8
            )
        )
    }
}

nonisolated struct ModelBackedMemoryMaintenanceService: AIMemoryMaintenanceService {
    let extractor: any AIMemoryExtractionClient
    let defaultModel: String
    var fallback: HeuristicMemoryMaintenanceService = HeuristicMemoryMaintenanceService()

    func refreshArtifacts(for conversation: ConversationThread) async -> ConversationMemoryArtifacts {
        let fallbackArtifacts = fallback.refreshArtifactsSynchronously(for: conversation)
        let visibleMessages = contextEligibleMessages(in: conversation)

        guard visibleMessages.count >= 2 else {
            return fallbackArtifacts
        }

        let archiveCandidateMessages = archiveCandidateMessages(
            from: visibleMessages,
            existingSegments: conversation.archiveSegments,
            protectedRecentMessages: 8
        )
        let recentMessages = Array(visibleMessages.suffix(10))
        let runtimeConfiguration = conversation.resolvedAIConfiguration(defaultModel: defaultModel)

        let extractionRequest = ConversationMemoryExtractionRequest(
            model: runtimeConfiguration.model,
            mode: AIContextAssembler.detectedMode(for: conversation).rawValue,
            conversationTitle: conversation.title,
            recentMessages: recentMessages.map(memoryPayload(from:)),
            existingFocusState: focusPayload(from: conversation.focusState),
            existingMemoryItems: conversation.memoryItems.map(\.text),
            archiveCandidateMessages: archiveCandidateMessages.map(memoryPayload(from:))
        )

        do {
            let extractionResponse = try await extractor.extractMemory(request: extractionRequest)
            return mergedArtifacts(
                from: fallbackArtifacts,
                extractionResponse: extractionResponse,
                recentMessages: recentMessages,
                archiveCandidateMessages: archiveCandidateMessages,
                fallbackMode: AIContextAssembler.detectedMode(for: conversation)
            )
        } catch {
            return fallbackArtifacts
        }
    }

    private func mergedArtifacts(
        from fallbackArtifacts: ConversationMemoryArtifacts,
        extractionResponse: ConversationMemoryExtractionResponse,
        recentMessages: [ChatMessage],
        archiveCandidateMessages: [ChatMessage],
        fallbackMode: ContextMode
    ) -> ConversationMemoryArtifacts {
        var mergedArtifacts = fallbackArtifacts
        let sourceMessageIDs = recentMessages.map(\.id)

        if let focusState = focusState(
            from: extractionResponse,
            fallbackMode: fallbackMode,
            sourceMessageIDs: sourceMessageIDs,
            existingFocusStateID: fallbackArtifacts.focusState?.id
        ) {
            mergedArtifacts.focusState = focusState
        }

        let extractedMemoryItems = memoryItems(
            from: extractionResponse,
            sourceMessageIDs: sourceMessageIDs
        )
        if extractedMemoryItems.isEmpty == false {
            mergedArtifacts.memoryItems = extractedMemoryItems
        }

        if let archiveSegment = archiveSegment(
            from: extractionResponse,
            sourceMessageIDs: archiveCandidateMessages.map(\.id)
        ) {
            var updatedSegments = fallbackArtifacts.archiveSegments
            if let index = updatedSegments.firstIndex(where: { $0.sourceMessageIDs == archiveSegment.sourceMessageIDs }) {
                updatedSegments[index] = archiveSegment
            } else {
                updatedSegments.append(archiveSegment)
            }
            mergedArtifacts.archiveSegments = Array(updatedSegments.suffix(24))
        }

        return mergedArtifacts
    }

    private func focusState(
        from response: ConversationMemoryExtractionResponse,
        fallbackMode: ContextMode,
        sourceMessageIDs: [UUID],
        existingFocusStateID: UUID?
    ) -> ConversationFocusState? {
        let resolvedMode = ContextMode(rawValue: response.kind?.trimmed.lowercased() ?? "") ?? fallbackMode
        let title = response.title?.nonEmptyTrimmed ?? "Current Focus"
        let focusNote = response.focusNote?.nonEmptyTrimmed ?? ""
        let openLoops = response.openLoops
            .compactMap(\.nonEmptyTrimmed)
            .prefix(4)
            .map { String($0.prefix(140)) }

        guard focusNote.isEmpty == false || openLoops.isEmpty == false else {
            return nil
        }

        if resolvedMode == .casual && openLoops.isEmpty && focusNote.isEmpty {
            return nil
        }

        return ConversationFocusState(
            id: existingFocusStateID ?? UUID(),
            kind: resolvedMode,
            title: title,
            focusNote: String(focusNote.prefix(1_500)),
            openLoops: Array(openLoops),
            sourceMessageIDs: sourceMessageIDs,
            updatedAt: .now
        )
    }

    private func memoryItems(
        from response: ConversationMemoryExtractionResponse,
        sourceMessageIDs: [UUID]
    ) -> [ConversationMemoryItem] {
        var uniqueTexts: [String] = []

        for candidate in response.memoryItems {
            guard let normalized = candidate.nonEmptyTrimmed?.collapseWhitespace() else {
                continue
            }

            if uniqueTexts.contains(normalized) {
                continue
            }

            uniqueTexts.append(normalized)
            if uniqueTexts.count >= 8 {
                break
            }
        }

        return uniqueTexts.map { text in
            ConversationMemoryItem(
                text: String(text.prefix(220)),
                keywords: derivedKeywords(from: text),
                sourceMessageIDs: sourceMessageIDs,
                updatedAt: .now
            )
        }
    }

    private func archiveSegment(
        from response: ConversationMemoryExtractionResponse,
        sourceMessageIDs: [UUID]
    ) -> ConversationArchiveSegment? {
        guard sourceMessageIDs.isEmpty == false,
              let summary = response.archiveSummary?.nonEmptyTrimmed
        else {
            return nil
        }

        return ConversationArchiveSegment(
            title: response.archiveTitle?.nonEmptyTrimmed ?? "Archived Context",
            summary: String(summary.prefix(1_200)),
            keywords: derivedKeywords(from: summary),
            openLoops: response.archiveOpenLoops
                .compactMap(\.nonEmptyTrimmed)
                .prefix(4)
                .map { String($0.prefix(140)) },
            sourceMessageIDs: sourceMessageIDs,
            updatedAt: .now
        )
    }
}

nonisolated private func contextEligibleMessages(in conversation: ConversationThread) -> [ChatMessage] {
    conversation.messages.filter { message in
        message.status != .failed &&
        message.role != .system &&
        (
            message.cleanedText.isEmpty == false ||
            message.cleanedThoughtSummary != nil ||
            message.attachments.isEmpty == false
        )
    }
}

nonisolated private func deriveFocusState(
    from messages: [ChatMessage],
    existingFocusState: ConversationFocusState?,
    mode: ContextMode,
    conversationTitle: String
) -> ConversationFocusState? {
    guard messages.isEmpty == false else {
        return nil
    }

    if mode == .casual, let existingFocusState, existingFocusState.openLoops.isEmpty {
        return nil
    }

    let focusMessages = Array(messages.suffix(mode == .casual ? 4 : 6))
    let latestFocusTitleSource = focusMessages.reversed().first { message in
        message.role == .user && message.cleanedText.isEmpty == false
    }?.cleanedText
    let title = latestFocusTitleSource.map { source in
        String(source.prefix(28)).trimmed
    } ?? existingFocusState?.title ?? conversationTitle

    let focusLines = focusMessages.map { message in
        let speaker = message.role == .assistant ? "Assistant" : "User"
        return "\(speaker): \(message.cleanedText.collapseWhitespace())"
    }
    let focusNote = focusLines.joined(separator: "\n")
    let openLoops = extractOpenLoops(from: focusMessages)
    let sourceMessageIDs = focusMessages.map(\.id)

    guard focusNote.nonEmptyTrimmed != nil || openLoops.isEmpty == false else {
        return nil
    }

    return ConversationFocusState(
        id: existingFocusState?.id ?? UUID(),
        kind: mode,
        title: title,
        focusNote: String(focusNote.prefix(1_500)),
        openLoops: openLoops,
        sourceMessageIDs: sourceMessageIDs,
        updatedAt: .now
    )
}

nonisolated private func deriveMemoryItems(from messages: [ChatMessage]) -> [ConversationMemoryItem] {
    let candidates = messages
        .filter { $0.role == .user }
        .dropLast(2)
        .compactMap(\.cleanedText.nonEmptyTrimmed)
        .filter { text in
            let normalized = text.lowercased()
            return [
                "喜欢", "希望", "请用", "尽量", "不要", "习惯", "更喜欢",
                "薄弱", "容易错", "总是错", "看不懂", "中文", "分步", "详细"
            ].contains(where: { normalized.contains($0) })
        }

    var uniqueTexts: [String] = []
    for candidate in candidates.reversed() {
        if uniqueTexts.contains(candidate) == false {
            uniqueTexts.append(candidate)
        }
        if uniqueTexts.count >= 8 {
            break
        }
    }

    return uniqueTexts.map { text in
        ConversationMemoryItem(
            text: String(text.prefix(220)),
            keywords: derivedKeywords(from: text)
        )
    }
}

nonisolated private func deriveArchiveSegments(
    from messages: [ChatMessage],
    existingSegments: [ConversationArchiveSegment],
    protectedRecentMessages: Int
) -> [ConversationArchiveSegment] {
    let candidateMessages = archiveCandidateMessages(
        from: messages,
        existingSegments: existingSegments,
        protectedRecentMessages: protectedRecentMessages
    )

    guard candidateMessages.isEmpty == false else {
        return existingSegments
    }

    let summary = summarizedArchiveText(for: candidateMessages)
    guard summary.isEmpty == false else {
        return existingSegments
    }

    let archiveTitleSource = candidateMessages.first { message in
        message.role == .user && message.cleanedText.isEmpty == false
    }?.cleanedText
    let title = archiveTitleSource.map { source in
        String(source.prefix(28)).trimmed
    } ?? "Archived Context"
    let sourceMessageIDs = candidateMessages.map(\.id)
    if existingSegments.contains(where: { $0.sourceMessageIDs == sourceMessageIDs }) {
        return existingSegments
    }

    var updatedSegments = existingSegments
    updatedSegments.append(
        ConversationArchiveSegment(
            title: title,
            summary: summary,
            keywords: derivedKeywords(from: summary),
            openLoops: extractOpenLoops(from: candidateMessages),
            sourceMessageIDs: sourceMessageIDs,
            updatedAt: .now
        )
    )

    return Array(updatedSegments.suffix(24))
}

nonisolated private func archiveCandidateMessages(
    from messages: [ChatMessage],
    existingSegments: [ConversationArchiveSegment],
    protectedRecentMessages: Int
) -> [ChatMessage] {
    guard messages.count > 14 || messages.reduce(0, { $0 + max($1.cleanedText.count, 24) }) > 8_000 else {
        return []
    }

    let protectedIDs = Set(messages.suffix(protectedRecentMessages).map(\.id))
    let archivedMessageIDs = Set(existingSegments.flatMap(\.sourceMessageIDs))

    let candidates = messages.filter { message in
        protectedIDs.contains(message.id) == false &&
        archivedMessageIDs.contains(message.id) == false
    }

    return Array(candidates.prefix(8))
}

nonisolated private func extractOpenLoops(from messages: [ChatMessage]) -> [String] {
    var loops: [String] = []

    for message in messages.reversed() where message.role == .user {
        guard let text = message.cleanedText.nonEmptyTrimmed else {
            continue
        }

        let normalized = text.lowercased()
        let isOpenLoop =
            text.contains("?") ||
            text.contains("？") ||
            normalized.contains("下一步") ||
            normalized.contains("继续") ||
            normalized.contains("为什么") ||
            normalized.contains("怎么")

        guard isOpenLoop else {
            continue
        }

        loops.append(String(text.prefix(140)))
        if loops.count >= 3 {
            break
        }
    }

    return loops.reversed()
}

nonisolated private func summarizedArchiveText(for messages: [ChatMessage]) -> String {
    String(
        messages
            .compactMap { message -> String? in
                guard let text = message.cleanedText.nonEmptyTrimmed else {
                    return nil
                }

                let speaker = message.role == .assistant ? "Assistant" : "User"
                return "\(speaker): \(text.collapseWhitespace())"
            }
            .joined(separator: "\n")
            .prefix(1_200)
    ).trimmed
}

nonisolated private func derivedKeywords(from text: String) -> [String] {
    let normalized = text.collapseWhitespace().lowercased()
    let wordMatches = normalized.matches(for: #"[a-z0-9_]{2,}"#)
    let cjkTokens = normalized.cjkBigrams()
    return Array(Set((wordMatches + cjkTokens).filter { $0.isEmpty == false }))
        .sorted()
        .prefix(12)
        .map { $0 }
}

nonisolated private func memoryPayload(from message: ChatMessage) -> ConversationMemoryMessagePayload {
    ConversationMemoryMessagePayload(
        id: message.id.uuidString,
        role: message.role.rawValue,
        text: message.cleanedText.collapseWhitespace()
    )
}

nonisolated private func focusPayload(from focusState: ConversationFocusState?) -> ConversationMemoryFocusPayload? {
    guard let focusState else {
        return nil
    }

    return ConversationMemoryFocusPayload(
        kind: focusState.kind.rawValue,
        title: focusState.title,
        focusNote: focusState.focusNote,
        openLoops: focusState.openLoops
    )
}
