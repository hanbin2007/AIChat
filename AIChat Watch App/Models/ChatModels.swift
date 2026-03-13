//
//  ChatModels.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation
import UIKit

nonisolated enum ChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system

    var geminiRole: String? {
        switch self {
        case .user:
            return "user"
        case .assistant:
            return "model"
        case .system:
            return nil
        }
    }
}

nonisolated enum ChatMessageStatus: String, Codable, Hashable {
    case sent
    case streaming
    case failed
}

nonisolated enum ContextMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case casual
    case teaching
    case task

    var id: String {
        rawValue
    }
}

nonisolated enum AISystemPromptMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case concise
    case `default`

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .concise:
            return L10n.tr("ai.system_prompt.concise")
        case .default:
            return L10n.tr("ai.system_prompt.default")
        }
    }
}

nonisolated enum AIThinkingIntensity: String, Codable, CaseIterable, Hashable, Identifiable {
    case fast
    case balanced
    case deep
    case extreme

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .fast:
            return L10n.tr("ai.thinking.fast")
        case .balanced:
            return L10n.tr("ai.thinking.balanced")
        case .deep:
            return L10n.tr("ai.thinking.deep")
        case .extreme:
            return L10n.tr("ai.thinking.extreme")
        }
    }

    var shortLabel: String {
        switch self {
        case .fast:
            return "LO"
        case .balanced:
            return "MID"
        case .deep:
            return "HI"
        case .extreme:
            return "MAX"
        }
    }

    func gemini3ThinkingLevel(for model: String) -> String? {
        switch self {
        case .fast:
            return "minimal"
        case .balanced:
            return "medium"
        case .deep:
            return "high"
        case .extreme:
            return AIModelCatalog.supportsExtremeThinking(model: model) ? nil : "high"
        }
    }

    var gemini25ThinkingBudget: Int {
        switch self {
        case .fast:
            return 0
        case .balanced:
            return 8_192
        case .deep:
            return 24_576
        case .extreme:
            return -1
        }
    }
}

nonisolated struct ConversationAIConfiguration: Codable, Equatable, Hashable {
    var model: String
    var thinkingIntensity: AIThinkingIntensity
    var systemPromptMode: AISystemPromptMode
    var customSystemPrompt: String?
    var usesGlobalPinnedMemory: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case thinkingIntensity
        case systemPromptMode
        case customSystemPrompt
        case usesGlobalPinnedMemory
    }

    init(
        model: String,
        thinkingIntensity: AIThinkingIntensity = .balanced,
        systemPromptMode: AISystemPromptMode = .concise,
        customSystemPrompt: String? = nil,
        usesGlobalPinnedMemory: Bool = false
    ) {
        self.model = model
        self.thinkingIntensity = thinkingIntensity
        self.systemPromptMode = systemPromptMode
        self.customSystemPrompt = customSystemPrompt?.nonEmptyTrimmed
        self.usesGlobalPinnedMemory = usesGlobalPinnedMemory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.thinkingIntensity = try container.decodeIfPresent(AIThinkingIntensity.self, forKey: .thinkingIntensity) ?? .balanced
        self.systemPromptMode = try container.decodeIfPresent(AISystemPromptMode.self, forKey: .systemPromptMode) ?? .concise
        self.customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt)?.nonEmptyTrimmed
        self.usesGlobalPinnedMemory = try container.decodeIfPresent(Bool.self, forKey: .usesGlobalPinnedMemory) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(thinkingIntensity, forKey: .thinkingIntensity)
        try container.encode(systemPromptMode, forKey: .systemPromptMode)
        try container.encode(customSystemPrompt?.nonEmptyTrimmed, forKey: .customSystemPrompt)
        try container.encode(usesGlobalPinnedMemory, forKey: .usesGlobalPinnedMemory)
    }
}

nonisolated struct ConversationFocusState: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: ContextMode
    var title: String
    var focusNote: String
    var openLoops: [String]
    var sourceMessageIDs: [UUID]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: ContextMode,
        title: String,
        focusNote: String,
        openLoops: [String] = [],
        sourceMessageIDs: [UUID] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.title = title.nonEmptyTrimmed ?? L10n.tr("context.current_focus")
        self.focusNote = focusNote.nonEmptyTrimmed ?? ""
        self.openLoops = openLoops
            .compactMap(\.nonEmptyTrimmed)
        self.sourceMessageIDs = sourceMessageIDs
        self.updatedAt = updatedAt
    }
}

nonisolated struct ConversationMemoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var keywords: [String]
    var sourceMessageIDs: [UUID]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        keywords: [String] = [],
        sourceMessageIDs: [UUID] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text.nonEmptyTrimmed ?? ""
        self.keywords = keywords
            .compactMap(\.nonEmptyTrimmed)
        self.sourceMessageIDs = sourceMessageIDs
        self.updatedAt = updatedAt
    }
}

nonisolated enum PinnedMemoryScope: String, Codable, Hashable, CaseIterable, Identifiable {
    case conversation
    case global

    var id: String {
        rawValue
    }
}

nonisolated struct PinnedMemoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var keywords: [String]
    var scope: PinnedMemoryScope
    var sourceMessageIDs: [UUID]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        keywords: [String] = [],
        scope: PinnedMemoryScope,
        sourceMessageIDs: [UUID] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.text = text.nonEmptyTrimmed ?? ""
        self.keywords = keywords
            .compactMap(\.nonEmptyTrimmed)
        self.scope = scope
        self.sourceMessageIDs = sourceMessageIDs
        self.updatedAt = updatedAt
    }
}

nonisolated struct ConversationArchiveSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var summary: String
    var keywords: [String]
    var openLoops: [String]
    var sourceMessageIDs: [UUID]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        keywords: [String] = [],
        openLoops: [String] = [],
        sourceMessageIDs: [UUID] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title.nonEmptyTrimmed ?? L10n.tr("context.archived")
        self.summary = summary.nonEmptyTrimmed ?? ""
        self.keywords = keywords
            .compactMap(\.nonEmptyTrimmed)
        self.openLoops = openLoops
            .compactMap(\.nonEmptyTrimmed)
        self.sourceMessageIDs = sourceMessageIDs
        self.updatedAt = updatedAt
    }
}

nonisolated enum ChatAttachmentKind: String, Codable, Hashable {
    case image
    case audio
}

nonisolated enum AttachmentProcessingError: LocalizedError {
    case unsupportedImage
    case unsupportedAudio
    case imageTooLarge(maximumBytes: Int)
    case audioTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return L10n.tr("attachment.error.unsupported_image")
        case .unsupportedAudio:
            return L10n.tr("attachment.error.unsupported_audio")
        case .imageTooLarge(let maximumBytes):
            let megabytes = Double(maximumBytes) / 1_000_000
            return L10n.format("attachment.error.image_too_large", megabytes)
        case .audioTooLarge(let maximumBytes):
            let megabytes = Double(maximumBytes) / 1_000_000
            return L10n.format("attachment.error.audio_too_large", megabytes)
        }
    }
}

nonisolated struct ChatAttachment: Identifiable, Codable, Hashable {
    static let maximumImagePayloadBytes = 1_500_000
    static let maximumAudioPayloadBytes = 4_000_000

    let id: UUID
    var kind: ChatAttachmentKind
    var filename: String
    var mimeType: String
    var data: Data
    var blobFilename: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var durationSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case filename
        case mimeType
        case data
        case blobFilename
        case pixelWidth
        case pixelHeight
        case durationSeconds
    }

    init(
        id: UUID = UUID(),
        kind: ChatAttachmentKind,
        filename: String,
        mimeType: String,
        data: Data,
        blobFilename: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.blobFilename = blobFilename?.nonEmptyTrimmed
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth)
        let pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight)
        let mimeType = try container.decode(String.self, forKey: .mimeType)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decodeIfPresent(ChatAttachmentKind.self, forKey: .kind) ??
            Self.inferredKind(
                mimeType: mimeType,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        self.filename = try container.decode(String.self, forKey: .filename)
        self.mimeType = mimeType
        self.data = try container.decode(Data.self, forKey: .data)
        self.blobFilename = try container.decodeIfPresent(String.self, forKey: .blobFilename)?.nonEmptyTrimmed
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(filename, forKey: .filename)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(data, forKey: .data)
        try container.encode(blobFilename?.nonEmptyTrimmed, forKey: .blobFilename)
        try container.encodeIfPresent(pixelWidth, forKey: .pixelWidth)
        try container.encodeIfPresent(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    }

    var previewImage: UIImage? {
        guard kind == .image else {
            return nil
        }

        return UIImage(data: data)
    }

    var sizeInBytes: Int {
        data.count
    }

    var isImage: Bool {
        kind == .image
    }

    var isAudio: Bool {
        kind == .audio
    }

    var shortSummary: String {
        switch kind {
        case .image:
            return L10n.tr("attachment.kind.image")
        case .audio:
            return L10n.tr("attachment.kind.audio")
        }
    }

    static func makeNormalizedImage(from rawData: Data, suggestedFilename: String?) throws -> ChatAttachment {
        guard let image = UIImage(data: rawData) else {
            throw AttachmentProcessingError.unsupportedImage
        }

        let filenameStem = URL(fileURLWithPath: suggestedFilename ?? "photo.jpg")
            .deletingPathExtension()
            .lastPathComponent
            .nonEmptyTrimmed ?? "photo"

        let compressionQualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42]
        var normalizedData = rawData

        for quality in compressionQualities {
            if let jpegData = image.jpegData(compressionQuality: quality) {
                normalizedData = jpegData
                if jpegData.count <= maximumImagePayloadBytes {
                    break
                }
            }
        }

        guard normalizedData.count <= maximumImagePayloadBytes else {
            throw AttachmentProcessingError.imageTooLarge(maximumBytes: maximumImagePayloadBytes)
        }

        return ChatAttachment(
            kind: .image,
            filename: "\(filenameStem)-\(UUID().uuidString.prefix(6)).jpg",
            mimeType: "image/jpeg",
            data: normalizedData,
            pixelWidth: Int(image.size.width),
            pixelHeight: Int(image.size.height)
        )
    }

    static func makeRecordedAudio(
        from rawData: Data,
        suggestedFilename: String?,
        durationSeconds: Double
    ) throws -> ChatAttachment {
        guard rawData.isEmpty == false else {
            throw AttachmentProcessingError.unsupportedAudio
        }

        guard rawData.count <= maximumAudioPayloadBytes else {
            throw AttachmentProcessingError.audioTooLarge(maximumBytes: maximumAudioPayloadBytes)
        }

        let filenameStem = URL(fileURLWithPath: suggestedFilename ?? "voice.wav")
            .deletingPathExtension()
            .lastPathComponent
            .nonEmptyTrimmed ?? "voice"

        return ChatAttachment(
            kind: .audio,
            filename: "\(filenameStem)-\(UUID().uuidString.prefix(6)).wav",
            mimeType: "audio/wav",
            data: rawData,
            durationSeconds: max(durationSeconds, 0)
        )
    }

    private static func inferredKind(
        mimeType: String,
        pixelWidth: Int?,
        pixelHeight: Int?
    ) -> ChatAttachmentKind {
        if mimeType.lowercased().hasPrefix("audio/") {
            return .audio
        }

        if pixelWidth != nil || pixelHeight != nil || mimeType.lowercased().hasPrefix("image/") {
            return .image
        }

        return .image
    }
}

typealias ChatImageAttachment = ChatAttachment

nonisolated struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: ChatRole
    var text: String
    var thoughtSummary: String?
    var createdAt: Date
    var attachments: [ChatAttachment]
    var status: ChatMessageStatus

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        thoughtSummary: String? = nil,
        createdAt: Date = .now,
        attachments: [ChatAttachment] = [],
        status: ChatMessageStatus = .sent
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thoughtSummary = thoughtSummary
        self.createdAt = createdAt
        self.attachments = attachments
        self.status = status
    }

    var cleanedText: String {
        text.trimmed
    }

    var cleanedThoughtSummary: String? {
        thoughtSummary?.nonEmptyTrimmed
    }

    var hasVisibleContent: Bool {
        cleanedText.isEmpty == false ||
        cleanedThoughtSummary != nil ||
        attachments.isEmpty == false ||
        status == .streaming
    }
}

nonisolated struct ConversationThread: Identifiable, Codable, Hashable {
    static var untitledTitle: String {
        L10n.tr("conversation.untitled")
    }

    private static let legacyUntitledTitles = Set([
        "New Chat",
        "新对话"
    ])

    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var messages: [ChatMessage]
    var aiConfiguration: ConversationAIConfiguration?
    var focusState: ConversationFocusState?
    var memoryItems: [ConversationMemoryItem]
    var pinnedMemories: [PinnedMemoryItem]
    var archiveSegments: [ConversationArchiveSegment]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case isFavorite
        case messages
        case aiConfiguration
        case focusState
        case memoryItems
        case pinnedMemories
        case archiveSegments
    }

    init(
        id: UUID = UUID(),
        title: String = ConversationThread.untitledTitle,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isFavorite: Bool = false,
        messages: [ChatMessage] = [],
        aiConfiguration: ConversationAIConfiguration? = nil,
        focusState: ConversationFocusState? = nil,
        memoryItems: [ConversationMemoryItem] = [],
        pinnedMemories: [PinnedMemoryItem] = [],
        archiveSegments: [ConversationArchiveSegment] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.messages = messages
        self.aiConfiguration = aiConfiguration
        self.focusState = focusState
        self.memoryItems = memoryItems
        self.pinnedMemories = pinnedMemories
        self.archiveSegments = archiveSegments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ConversationThread.untitledTitle
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        self.aiConfiguration = try container.decodeIfPresent(ConversationAIConfiguration.self, forKey: .aiConfiguration)
        self.focusState = try container.decodeIfPresent(ConversationFocusState.self, forKey: .focusState)
        self.memoryItems = try container.decodeIfPresent([ConversationMemoryItem].self, forKey: .memoryItems) ?? []
        self.pinnedMemories = try container.decodeIfPresent([PinnedMemoryItem].self, forKey: .pinnedMemories) ?? []
        self.archiveSegments = try container.decodeIfPresent([ConversationArchiveSegment].self, forKey: .archiveSegments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(aiConfiguration, forKey: .aiConfiguration)
        try container.encodeIfPresent(focusState, forKey: .focusState)
        try container.encode(memoryItems, forKey: .memoryItems)
        try container.encode(pinnedMemories, forKey: .pinnedMemories)
        try container.encode(archiveSegments, forKey: .archiveSegments)
    }

    static func empty(
        now: Date = .now,
        aiConfiguration: ConversationAIConfiguration? = nil
    ) -> ConversationThread {
        ConversationThread(
            createdAt: now,
            updatedAt: now,
            aiConfiguration: aiConfiguration
        )
    }

    static func sortsByMostRecentFirst(_ lhs: ConversationThread, _ rhs: ConversationThread) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }

            return lhs.createdAt > rhs.createdAt
        }

        return lhs.updatedAt > rhs.updatedAt
    }

    var previewText: String {
        guard let lastMessage = messages.last(where: \.hasVisibleContent) else {
            return L10n.tr("conversation.preview.empty")
        }

        if lastMessage.status == .streaming, lastMessage.cleanedText.isEmpty {
            if let thoughtSummary = lastMessage.cleanedThoughtSummary {
                return L10n.format("conversation.preview.thinking", thoughtSummary)
            }
            return L10n.tr("conversation.preview.streaming")
        }

        if lastMessage.status == .failed, lastMessage.cleanedText.isEmpty {
            return L10n.tr("conversation.preview.failed")
        }

        if let text = lastMessage.cleanedText.nonEmptyTrimmed {
            return text.previewSnippet(maxLength: 220)
        }

        if let thoughtSummary = lastMessage.cleanedThoughtSummary {
            return thoughtSummary.previewSnippet(maxLength: 220)
        }

        return attachmentSummary(for: lastMessage.attachments)
    }

    var messageCount: Int {
        messages.lazy.reduce(into: 0) { count, message in
            if message.hasVisibleContent {
                count += 1
            }
        }
    }

    var containsAudioAttachments: Bool {
        messages.lazy.contains { message in
            message.attachments.contains(where: \.isAudio)
        }
    }

    var containsImageAttachments: Bool {
        messages.lazy.contains { message in
            message.attachments.contains(where: \.isImage)
        }
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = max(updatedAt, message.createdAt)

        if Self.isUntitledTitle(title),
           message.role == .user,
           let suggested = Self.suggestedTitle(
               from: message.text,
               attachments: message.attachments
           ) {
            title = suggested
        }
    }

    static func suggestedTitle(from text: String, attachments: [ChatAttachment] = []) -> String? {
        let collapsed = text.collapseWhitespace().nonEmptyTrimmed
        if let collapsed {
            let limit = 26
            guard collapsed.count > limit else {
                return collapsed
            }

            let truncated = String(collapsed.prefix(limit)).trimmed
            return truncated.isEmpty ? nil : "\(truncated)..."
        }

        if attachments.contains(where: \.isAudio) {
            return L10n.tr("conversation.title.voice")
        }

        if attachments.contains(where: \.isImage) {
            return L10n.tr("conversation.title.photo")
        }

        return nil
    }

    mutating func clearMessages() {
        messages.removeAll()
        focusState = nil
        memoryItems.removeAll()
        pinnedMemories.removeAll()
        archiveSegments.removeAll()
        updatedAt = .now
    }

    mutating func updateTitle(_ newTitle: String) {
        title = newTitle.nonEmptyTrimmed ?? Self.untitledTitle
        updatedAt = .now
    }

    mutating func updateAIConfiguration(_ newConfiguration: ConversationAIConfiguration?) {
        aiConfiguration = newConfiguration
        updatedAt = .now
    }

    mutating func updateFavorite(_ newValue: Bool) {
        isFavorite = newValue
        updatedAt = .now
    }

    mutating func updateFocusState(_ newFocusState: ConversationFocusState?) {
        focusState = newFocusState
        updatedAt = .now
    }

    mutating func replaceMemoryItems(_ items: [ConversationMemoryItem]) {
        memoryItems = items
        updatedAt = .now
    }

    mutating func replacePinnedMemories(_ items: [PinnedMemoryItem]) {
        pinnedMemories = items
        updatedAt = .now
    }

    mutating func replaceArchiveSegments(_ segments: [ConversationArchiveSegment]) {
        archiveSegments = segments
        updatedAt = .now
    }

    mutating func upsertMessage(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        updatedAt = .now
    }

    mutating func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        updatedAt = .now
    }

    private func attachmentSummary(for attachments: [ChatAttachment]) -> String {
        let imageCount = attachments.filter(\.isImage).count
        let audioCount = attachments.filter(\.isAudio).count

        switch (imageCount, audioCount) {
        case (0, 1):
            return L10n.tr("conversation.attachment.voice.one")
        case (0, let audioCount) where audioCount > 1:
            return L10n.format("conversation.attachment.voice.many", audioCount)
        case (1, 0):
            return L10n.tr("conversation.attachment.image.one")
        case (let imageCount, 0) where imageCount > 1:
            return L10n.format("conversation.attachment.image.many", imageCount)
        default:
            return L10n.format("conversation.attachment.total", attachments.count)
        }
    }

    private static func isUntitledTitle(_ title: String) -> Bool {
        legacyUntitledTitles.contains(title) || title == untitledTitle
    }
}

nonisolated extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyTrimmed: String? {
        let trimmedValue = trimmed
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func collapseWhitespace() -> String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func previewSnippet(maxLength: Int) -> String {
        let normalized = collapseWhitespace().trimmed
        guard normalized.count > maxLength else {
            return normalized
        }

        let truncatedLength = max(maxLength - 3, 1)
        let truncated = String(normalized.prefix(truncatedLength)).trimmed
        return truncated.isEmpty ? String(normalized.prefix(maxLength)) : "\(truncated)..."
    }

    func matches(for pattern: String) -> [String] {
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return regex.matches(in: self, range: nsRange).compactMap { match in
            Range(match.range, in: self).map { String(self[$0]) }
        }
    }

    func cjkBigrams() -> [String] {
        let scalars = Array(unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        })
        guard scalars.count >= 2 else {
            return []
        }

        return (0..<(scalars.count - 1)).map { index in
            String(String.UnicodeScalarView([scalars[index], scalars[index + 1]]))
        }
    }
}

nonisolated extension ConversationThread {
    func resolvedAIConfiguration(defaultModel: String) -> ConversationAIConfiguration {
        if let aiConfiguration {
            return aiConfiguration
        }

        return ConversationAIConfiguration(model: defaultModel)
    }
}
