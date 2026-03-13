//
//  PromptPreset.swift
//  AIChat
//
//  Created by Codex on 2026/3/12.
//

import Foundation

nonisolated enum PromptPresetKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case conversation
    case transcription

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .conversation:
            return L10n.tr("prompt_preset.kind.conversation")
        case .transcription:
            return L10n.tr("prompt_preset.kind.transcription")
        }
    }
}

nonisolated struct PromptPreset: Identifiable, Codable, Equatable, Hashable {
    static let builtInConversationID = UUID(uuidString: "0C68F5A8-9F83-42A3-9D02-93ECAAB6E7F4")!
    static let builtInTranscriptionID = UUID(uuidString: "9E0B4A60-803E-47E8-8B9A-B77D93C5C1E7")!

    let id: UUID
    var kind: PromptPresetKind
    var title: String
    var content: String
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case content
        case isBuiltIn
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        kind: PromptPresetKind,
        title: String,
        content: String,
        isBuiltIn: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.title = title.nonEmptyTrimmed ?? kind.displayName
        self.content = content.nonEmptyTrimmed ?? ""
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decodeIfPresent(PromptPresetKind.self, forKey: .kind) ?? .conversation
        self.title = try container.decodeIfPresent(String.self, forKey: .title)?.nonEmptyTrimmed ?? kind.displayName
        self.content = try container.decodeIfPresent(String.self, forKey: .content)?.nonEmptyTrimmed ?? ""
        self.isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title.nonEmptyTrimmed ?? kind.displayName, forKey: .title)
        try container.encode(content.nonEmptyTrimmed ?? "", forKey: .content)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var previewText: String {
        content.collapseWhitespace().nonEmptyTrimmed ?? ""
    }

    func updated(kind: PromptPresetKind, title: String, content: String) -> PromptPreset {
        PromptPreset(
            id: id,
            kind: kind,
            title: title,
            content: content,
            isBuiltIn: isBuiltIn,
            createdAt: createdAt,
            updatedAt: .now
        )
    }

    static var builtInPresets: [PromptPreset] {
        [
            PromptPreset(
                id: builtInConversationID,
                kind: .conversation,
                title: L10n.tr("prompt_preset.builtin.conversation.title"),
                content: AIContextAssembler.conciseSystemPrompt,
                isBuiltIn: true,
                createdAt: .distantPast,
                updatedAt: .distantPast
            ),
            PromptPreset(
                id: builtInTranscriptionID,
                kind: .transcription,
                title: L10n.tr("prompt_preset.builtin.transcription.title"),
                content: VoiceTranscriptionPromptBuilder.systemPrompt,
                isBuiltIn: true,
                createdAt: .distantPast,
                updatedAt: .distantPast
            )
        ]
    }

    static func resolvedLibrary(from storedPresets: [PromptPreset]) -> [PromptPreset] {
        var presetsByID = Dictionary(
            uniqueKeysWithValues: builtInPresets.map { ($0.id, $0) }
        )

        for preset in storedPresets {
            let normalized = PromptPreset(
                id: preset.id,
                kind: preset.kind,
                title: preset.title,
                content: preset.content,
                isBuiltIn: preset.isBuiltIn,
                createdAt: preset.createdAt,
                updatedAt: preset.updatedAt
            )

            if normalized.isBuiltIn, builtInPresets.contains(where: { $0.id == normalized.id }) {
                continue
            }

            presetsByID[normalized.id] = normalized
        }

        return presetsByID.values.sorted(by: PromptPreset.sort)
    }

    private static func sort(lhs: PromptPreset, rhs: PromptPreset) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }

        if lhs.isBuiltIn != rhs.isBuiltIn {
            return lhs.isBuiltIn && rhs.isBuiltIn == false
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
