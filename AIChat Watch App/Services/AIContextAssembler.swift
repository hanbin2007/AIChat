//
//  AIContextAssembler.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/10.
//

import Foundation

struct AssembledContext: Equatable {
    var systemPrompt: String?
    var mode: ContextMode
    var prefaceText: String?
    var recentMessages: [ChatMessage]
}

nonisolated enum AIContextAssembler {
    static let conciseSystemPrompt =
        """
        You are AIChat on Apple devices.
        Keep answers clear, concise, and easy to scan on a small screen unless the user explicitly asks for detail.
        If a user turn includes audio attachments, treat the speech in the audio as the user's request and answer it directly instead of only describing or transcribing the audio.
        When memory context is provided, treat it as support material rather than a fresh user request. Prefer the newest raw conversation turns if memory conflicts with them.
        """

    private enum ReplyBudget {
        static let recentProtectedMessages = 4
        static let archiveSegmentCountCasual = 1
        static let archiveSegmentCountFocused = 2
        static let archiveSegmentCharactersCasual = 800
        static let archiveSegmentCharactersFocused = 1_200
        static let focusCharacters = 1_500
        static let focusCharactersCompact = 600
        static let casualMemoryCharacters = 1_200
        static let focusedMemoryCharacters = 2_000
        static let casualMaxMessages = 12
        static let focusedMaxMessages = 14
        static let casualMaxCharacters = 10_000
        static let focusedMaxCharacters = 16_000
        static let transcriptionRecentMessages = 4
        static let transcriptionTotalCharacters = 3_200
        static let transcriptionTermCharacters = 400
        static let maxInlineAttachmentBytes = 4_000_000
    }

    static func systemPrompt(for configuration: ConversationAIConfiguration) -> String? {
        if let customSystemPrompt = configuration.customSystemPrompt?.nonEmptyTrimmed {
            return customSystemPrompt
        }

        switch configuration.systemPromptMode {
        case .concise:
            return conciseSystemPrompt
        case .default:
            return nil
        }
    }

    static func assembleReplyContext(
        for conversation: ConversationThread,
        configuration: ConversationAIConfiguration
    ) -> AssembledContext {
        let mode = detectedMode(for: conversation)
        let recentMessages = selectRecentMessages(from: conversation.messages, mode: mode)
        let query = currentQuery(from: recentMessages, focusState: conversation.focusState, title: conversation.title)
        let pinnedMemories = selectPinnedMemories(from: conversation.pinnedMemories, query: query, mode: mode)
        let memoryItems = selectMemoryItems(from: conversation.memoryItems, query: query, mode: mode)
        let archiveSegments = selectArchiveSegments(from: conversation.archiveSegments, query: query, mode: mode)
        let focusState = includedFocusState(for: conversation.focusState, mode: mode)

        return AssembledContext(
            systemPrompt: systemPrompt(for: configuration),
            mode: mode,
            prefaceText: prefaceText(
                mode: mode,
                focusState: focusState,
                pinnedMemories: pinnedMemories,
                memoryItems: memoryItems,
                archiveSegments: archiveSegments
            ),
            recentMessages: recentMessages
        )
    }

    static func transcriptionContextSummary(for conversation: ConversationThread) -> String? {
        let mode = detectedMode(for: conversation)
        let recentLines = selectTranscriptionLines(from: conversation.messages)
        let focusText = compactFocusText(for: conversation.focusState, mode: mode)
        let memoryText = compactMemoryTerms(
            pinnedMemories: conversation.pinnedMemories,
            memoryItems: conversation.memoryItems,
            focusState: conversation.focusState
        )

        var sections: [String] = []

        if recentLines.isEmpty == false {
            sections.append("Recent conversation:\n\(recentLines.joined(separator: "\n"))")
        }

        if let focusText {
            sections.append("Current focus:\n\(focusText)")
        }

        if let memoryText {
            sections.append("Names and terms:\n\(memoryText)")
        }

        return trimJoinedSections(sections, to: ReplyBudget.transcriptionTotalCharacters)
    }

    static func detectedMode(for conversation: ConversationThread) -> ContextMode {
        if let kind = conversation.focusState?.kind {
            let recentSignal = detectSignal(in: conversation.messages.suffix(6).map(\.cleanedText).joined(separator: "\n"))
            if recentSignal == .casual {
                return kind == .casual ? .casual : kind
            }
        }

        let windowText = conversation.messages
            .suffix(8)
            .map(\.cleanedText)
            .joined(separator: "\n")

        return detectSignal(in: windowText)
    }

    private static func detectSignal(in text: String) -> ContextMode {
        let normalized = text.lowercased()
        let teachingKeywords = [
            "数学", "物理", "化学", "函数", "导数", "积分", "几何", "概率", "数列",
            "牛顿", "电场", "磁场", "受力", "方程", "化学方程式", "解题", "推导", "证明", "讲解",
            "思路", "错题", "订正", "公式", "题目", "高考", "解析"
        ]
        let taskKeywords = [
            "总结", "方案", "比较", "分析", "实现", "设计", "计划", "安排", "整理", "提纲"
        ]

        let containsFormulaLikeText = normalized.range(
            of: #"([a-z]\s*=\s*|[\+\-\*\/\^]=?|sin|cos|tan|log|ln|\d+\s*[a-zA-Z])"#,
            options: .regularExpression
        ) != nil

        if containsFormulaLikeText || teachingKeywords.contains(where: { normalized.contains($0) }) {
            return .teaching
        }

        if taskKeywords.contains(where: { normalized.contains($0) }) {
            return .task
        }

        return .casual
    }

    private static func selectRecentMessages(
        from messages: [ChatMessage],
        mode: ContextMode
    ) -> [ChatMessage] {
        let maxMessages = mode == .casual ? ReplyBudget.casualMaxMessages : ReplyBudget.focusedMaxMessages
        let maxCharacters = mode == .casual ? ReplyBudget.casualMaxCharacters : ReplyBudget.focusedMaxCharacters

        let eligibleMessages = messages.filter { message in
            message.status != .failed &&
            message.role != .system &&
            message.hasVisibleContent
        }

        var selectedMessages: [ChatMessage] = []
        var consumedCharacters = 0
        var consumedAttachmentBytes = 0

        for message in eligibleMessages.reversed() {
            let messageCharacters = max(message.cleanedText.count, 24)
            let attachmentBytes = message.attachments.reduce(0) { partial, attachment in
                partial + attachment.sizeInBytes
            }

            let isProtectedWindow = selectedMessages.count < ReplyBudget.recentProtectedMessages
            let exceedsBudget =
                selectedMessages.isEmpty == false &&
                isProtectedWindow == false &&
                (
                    selectedMessages.count >= maxMessages ||
                    consumedCharacters + messageCharacters > maxCharacters ||
                    consumedAttachmentBytes + attachmentBytes > ReplyBudget.maxInlineAttachmentBytes
                )

            if exceedsBudget {
                break
            }

            selectedMessages.append(message)
            consumedCharacters += messageCharacters
            consumedAttachmentBytes += attachmentBytes
        }

        return selectedMessages.reversed()
    }

    private static func selectTranscriptionLines(from messages: [ChatMessage]) -> [String] {
        var lines: [String] = []
        var consumedCharacters = 0

        for message in messages.reversed() {
            guard lines.count < ReplyBudget.transcriptionRecentMessages,
                  message.status != .failed,
                  message.role != .system,
                  let text = message.cleanedText.nonEmptyTrimmed
            else {
                continue
            }

            let speaker = message.role == .assistant ? "Assistant" : "User"
            let line = "\(speaker): \(text.collapseWhitespace())"
            let nextLength = consumedCharacters + line.count
            if lines.isEmpty == false, nextLength > ReplyBudget.transcriptionTotalCharacters {
                break
            }

            lines.append(line)
            consumedCharacters = nextLength
        }

        return lines.reversed()
    }

    private static func includedFocusState(
        for focusState: ConversationFocusState?,
        mode: ContextMode
    ) -> ConversationFocusState? {
        guard let focusState else {
            return nil
        }

        if mode == .casual && focusState.openLoops.isEmpty {
            return nil
        }

        return focusState
    }

    private static func selectPinnedMemories(
        from items: [PinnedMemoryItem],
        query: String,
        mode: ContextMode
    ) -> [PinnedMemoryItem] {
        let budget = mode == .casual ? ReplyBudget.casualMemoryCharacters : ReplyBudget.focusedMemoryCharacters
        let sorted = items.sorted {
            score(text: $0.text, keywords: $0.keywords, updatedAt: $0.updatedAt, query: query, boost: 6) >
            score(text: $1.text, keywords: $1.keywords, updatedAt: $1.updatedAt, query: query, boost: 6)
        }

        return trimItems(sorted, budget: budget) { $0.text.count }
    }

    private static func selectMemoryItems(
        from items: [ConversationMemoryItem],
        query: String,
        mode: ContextMode
    ) -> [ConversationMemoryItem] {
        let budget = mode == .casual ? ReplyBudget.casualMemoryCharacters : ReplyBudget.focusedMemoryCharacters
        let sorted = items.sorted {
            score(text: $0.text, keywords: $0.keywords, updatedAt: $0.updatedAt, query: query, boost: 2) >
            score(text: $1.text, keywords: $1.keywords, updatedAt: $1.updatedAt, query: query, boost: 2)
        }

        return trimItems(sorted, budget: budget) { $0.text.count }
    }

    private static func selectArchiveSegments(
        from segments: [ConversationArchiveSegment],
        query: String,
        mode: ContextMode
    ) -> [ConversationArchiveSegment] {
        let maxCount = mode == .casual ? ReplyBudget.archiveSegmentCountCasual : ReplyBudget.archiveSegmentCountFocused
        let perSegmentLimit = mode == .casual ? ReplyBudget.archiveSegmentCharactersCasual : ReplyBudget.archiveSegmentCharactersFocused

        return segments
            .sorted {
                score(text: $0.summary, keywords: $0.keywords, updatedAt: $0.updatedAt, query: query, boost: 1) >
                score(text: $1.summary, keywords: $1.keywords, updatedAt: $1.updatedAt, query: query, boost: 1)
            }
            .prefix(maxCount)
            .map { segment in
                var trimmed = segment
                trimmed.summary = trimText(segment.summary, limit: perSegmentLimit)
                trimmed.openLoops = segment.openLoops.map { trimText($0, limit: 120) }
                return trimmed
            }
    }

    private static func currentQuery(
        from recentMessages: [ChatMessage],
        focusState: ConversationFocusState?,
        title: String
    ) -> String {
        if let latestUserText = recentMessages.reversed().first(where: { $0.role == .user })?.cleanedText.nonEmptyTrimmed {
            return latestUserText
        }

        if let focusNote = focusState?.focusNote.nonEmptyTrimmed {
            return focusNote
        }

        return title
    }

    private static func prefaceText(
        mode: ContextMode,
        focusState: ConversationFocusState?,
        pinnedMemories: [PinnedMemoryItem],
        memoryItems: [ConversationMemoryItem],
        archiveSegments: [ConversationArchiveSegment]
    ) -> String? {
        guard focusState != nil ||
                pinnedMemories.isEmpty == false ||
                memoryItems.isEmpty == false ||
                archiveSegments.isEmpty == false
        else {
            return nil
        }

        var sections: [String] = []

        sections.append(
            """
            Context preface:
            This is support memory for the next reply, not a fresh user turn.
            Prefer the newest raw messages if anything below conflicts with them.
            Current mode: \(mode.rawValue)
            """
        )

        if let focusState {
            var focusLines = [
                "Title: \(focusState.title)",
                "Focus: \(trimText(focusState.focusNote, limit: ReplyBudget.focusCharacters))"
            ]
            if focusState.openLoops.isEmpty == false {
                focusLines.append("Open loops: \(focusState.openLoops.joined(separator: " | "))")
            }
            sections.append("Current focus:\n\(focusLines.joined(separator: "\n"))")
        }

        if pinnedMemories.isEmpty == false {
            let lines = pinnedMemories.map { "- \($0.text)" }
            sections.append("Pinned memory:\n\(lines.joined(separator: "\n"))")
        }

        if memoryItems.isEmpty == false {
            let lines = memoryItems.map { "- \($0.text)" }
            sections.append("Relevant conversation memory:\n\(lines.joined(separator: "\n"))")
        }

        if archiveSegments.isEmpty == false {
            let lines = archiveSegments.map { segment in
                var archiveLine = "- \(segment.title): \(segment.summary)"
                if segment.openLoops.isEmpty == false {
                    archiveLine.append(" [Open loops: \(segment.openLoops.joined(separator: " | "))]")
                }
                return archiveLine
            }
            sections.append("Archived context:\n\(lines.joined(separator: "\n"))")
        }

        return trimJoinedSections(sections, to: mode == .casual ? 2_400 : 6_000)
    }

    private static func compactFocusText(
        for focusState: ConversationFocusState?,
        mode: ContextMode
    ) -> String? {
        guard let focusState else {
            return nil
        }

        if mode == .casual && focusState.openLoops.isEmpty {
            return nil
        }

        var lines = [
            "Title: \(focusState.title)",
            "Focus: \(trimText(focusState.focusNote, limit: ReplyBudget.focusCharactersCompact))"
        ]
        if focusState.openLoops.isEmpty == false {
            lines.append("Open loops: \(focusState.openLoops.joined(separator: " | "))")
        }
        return trimJoinedSections(lines, to: ReplyBudget.focusCharactersCompact)
    }

    private static func compactMemoryTerms(
        pinnedMemories: [PinnedMemoryItem],
        memoryItems: [ConversationMemoryItem],
        focusState: ConversationFocusState?
    ) -> String? {
        var candidates: [String] = []
        candidates.append(contentsOf: pinnedMemories.flatMap(\.keywords))
        candidates.append(contentsOf: memoryItems.flatMap(\.keywords))
        if let focusState {
            candidates.append(contentsOf: normalizedSearchTokens(in: focusState.focusNote))
        }

        let terms = Array(Set(candidates.map { $0.trimmed }.filter { $0.isEmpty == false }))
            .sorted()
        guard terms.isEmpty == false else {
            return nil
        }

        return trimText(terms.joined(separator: ", "), limit: ReplyBudget.transcriptionTermCharacters)
    }

    private static func score(
        text: String,
        keywords: [String],
        updatedAt: Date,
        query: String,
        boost: Int
    ) -> Int {
        let queryTokens = Set(normalizedSearchTokens(in: query))
        let textTokens = Set(normalizedSearchTokens(in: text) + keywords.map { $0.lowercased() })
        let overlap = queryTokens.intersection(textTokens).count
        let recencyHours = max(0, Int(Date().timeIntervalSince(updatedAt) / 3_600))
        let recencyScore = max(0, 72 - min(recencyHours, 72))
        return overlap * 12 + recencyScore + boost
    }

    private static func normalizedSearchTokens(in text: String) -> [String] {
        let collapsed = text.collapseWhitespace().lowercased()
        guard collapsed.isEmpty == false else {
            return []
        }

        var tokens: [String] = []
        let nsRange = NSRange(collapsed.startIndex..<collapsed.endIndex, in: collapsed)
        let regex = try? NSRegularExpression(pattern: #"[a-z0-9_]+"#)
        regex?.matches(in: collapsed, range: nsRange).compactMap { match in
            Range(match.range, in: collapsed).map { String(collapsed[$0]) }
        }.forEach { tokens.append($0) }

        let cjkScalars = Array(collapsed.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        })
        if cjkScalars.count >= 2 {
            for index in 0..<(cjkScalars.count - 1) {
                tokens.append(String(String.UnicodeScalarView([cjkScalars[index], cjkScalars[index + 1]])))
            }
        }

        return tokens
    }

    private static func trimItems<T>(
        _ items: [T],
        budget: Int,
        cost: (T) -> Int
    ) -> [T] {
        var trimmed: [T] = []
        var consumed = 0

        for item in items {
            let nextCost = max(cost(item), 24)
            if trimmed.isEmpty == false, consumed + nextCost > budget {
                break
            }
            trimmed.append(item)
            consumed += nextCost
        }

        return trimmed
    }

    private static func trimJoinedSections(_ sections: [String], to limit: Int) -> String? {
        let filtered = sections.compactMap(\.nonEmptyTrimmed)
        guard filtered.isEmpty == false else {
            return nil
        }

        var output = ""
        for section in filtered {
            let candidate = output.isEmpty ? section : "\(output)\n\n\(section)"
            if output.isEmpty == false, candidate.count > limit {
                break
            }
            output = trimText(candidate, limit: limit)
        }

        return output.nonEmptyTrimmed
    }

    private static func trimText(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let prefix = String(text.prefix(limit))
        return prefix.trimmed
    }
}
