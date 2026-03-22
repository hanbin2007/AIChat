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

nonisolated enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int64.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value):
            hasher.combine(0)
            hasher.combine(value)
        case .integer(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .number(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .object(let value):
            hasher.combine(4)
            for key in value.keys.sorted() {
                hasher.combine(key)
                hasher.combine(value[key])
            }
        case .array(let value):
            hasher.combine(5)
            for item in value {
                hasher.combine(item)
            }
        case .null:
            hasher.combine(6)
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }

        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }

        return value
    }
}

nonisolated struct GeminiPartPayload: Codable, Equatable, Hashable, Sendable {
    private var rawObject: [String: JSONValue]

    init(
        text: String? = nil,
        inlineData: GeminiPartInlineData? = nil,
        thought: Bool? = nil,
        thoughtSignature: String? = nil
    ) {
        var rawObject: [String: JSONValue] = [:]
        if let text {
            rawObject["text"] = .string(text)
        }
        if let inlineData {
            rawObject["inlineData"] = .object([
                "mimeType": .string(inlineData.mimeType),
                "data": .string(inlineData.data)
            ])
        }
        if let thought {
            rawObject["thought"] = .bool(thought)
        }
        if let thoughtSignature {
            rawObject["thoughtSignature"] = .string(thoughtSignature)
        }

        self.rawObject = rawObject
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawObject = try container.decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawObject)
    }

    var text: String? {
        value(forKeys: "text")?.stringValue
    }

    var inlineData: GeminiPartInlineData? {
        guard let object = value(forKeys: "inlineData", "inline_data")?.objectValue,
              let mimeType = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue,
              let data = object["data"]?.stringValue
        else {
            return nil
        }

        return GeminiPartInlineData(mimeType: mimeType, data: data)
    }

    var thought: Bool? {
        value(forKeys: "thought")?.boolValue
    }

    var thoughtSignature: String? {
        value(forKeys: "thoughtSignature", "thought_signature")?.stringValue
    }

    var hasNonSignaturePayload: Bool {
        for (key, value) in rawObject {
            switch key {
            case "thought", "thoughtSignature", "thought_signature":
                continue
            case "text":
                if let text = value.stringValue, text.isEmpty {
                    continue
                }
                return true
            default:
                return true
            }
        }

        return false
    }

    var hasRecoverableContent: Bool {
        text?.isEmpty == false ||
        inlineData != nil ||
        rawObject.isEmpty == false
    }

    private func value(forKeys keys: String...) -> JSONValue? {
        for key in keys {
            if let value = rawObject[key] {
                return value
            }
        }

        return nil
    }
}

nonisolated struct GeminiPartInlineData: Codable, Equatable, Hashable, Sendable {
    var mimeType: String
    var data: String
}

typealias GeminiPart = GeminiPartPayload
typealias GeminiInlineData = GeminiPartInlineData

nonisolated struct ConversationAIConfiguration: Codable, Equatable, Hashable {
    var model: String
    var thinkingIntensity: AIThinkingIntensity
    var systemPromptMode: AISystemPromptMode
    var customSystemPrompt: String?
    var usesGlobalPinnedMemory: Bool
    var usesGoogleSearch: Bool
    var usesCodeExecution: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case thinkingIntensity
        case systemPromptMode
        case customSystemPrompt
        case usesGlobalPinnedMemory
        case usesGoogleSearch
        case usesCodeExecution
    }

    init(
        model: String,
        thinkingIntensity: AIThinkingIntensity = .balanced,
        systemPromptMode: AISystemPromptMode = .concise,
        customSystemPrompt: String? = nil,
        usesGlobalPinnedMemory: Bool = false,
        usesGoogleSearch: Bool = false,
        usesCodeExecution: Bool = false
    ) {
        self.model = model
        self.thinkingIntensity = thinkingIntensity
        self.systemPromptMode = systemPromptMode
        self.customSystemPrompt = customSystemPrompt?.nonEmptyTrimmed
        self.usesGlobalPinnedMemory = usesGlobalPinnedMemory
        self.usesGoogleSearch = usesGoogleSearch
        self.usesCodeExecution = usesCodeExecution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.thinkingIntensity = try container.decodeIfPresent(AIThinkingIntensity.self, forKey: .thinkingIntensity) ?? .balanced
        self.systemPromptMode = try container.decodeIfPresent(AISystemPromptMode.self, forKey: .systemPromptMode) ?? .concise
        self.customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt)?.nonEmptyTrimmed
        self.usesGlobalPinnedMemory = try container.decodeIfPresent(Bool.self, forKey: .usesGlobalPinnedMemory) ?? false
        self.usesGoogleSearch = try container.decodeIfPresent(Bool.self, forKey: .usesGoogleSearch) ?? false
        self.usesCodeExecution = try container.decodeIfPresent(Bool.self, forKey: .usesCodeExecution) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(thinkingIntensity, forKey: .thinkingIntensity)
        try container.encode(systemPromptMode, forKey: .systemPromptMode)
        try container.encode(customSystemPrompt?.nonEmptyTrimmed, forKey: .customSystemPrompt)
        try container.encode(usesGlobalPinnedMemory, forKey: .usesGlobalPinnedMemory)
        try container.encode(usesGoogleSearch, forKey: .usesGoogleSearch)
        try container.encode(usesCodeExecution, forKey: .usesCodeExecution)
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

nonisolated struct ChatAttachment: Identifiable, Codable, Hashable, Sendable {
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

    static func makeModelGeneratedImage(
        from rawData: Data,
        mimeType: String,
        suggestedFilename: String? = nil
    ) throws -> ChatAttachment {
        guard let image = UIImage(data: rawData) else {
            throw AttachmentProcessingError.unsupportedImage
        }

        let normalizedMimeType = mimeType.nonEmptyTrimmed ?? "image/png"
        let fileExtension = preferredImageFileExtension(for: normalizedMimeType)
        let filenameStem = URL(fileURLWithPath: suggestedFilename ?? "generated-image.\(fileExtension)")
            .deletingPathExtension()
            .lastPathComponent
            .nonEmptyTrimmed ?? "generated-image"

        return ChatAttachment(
            kind: .image,
            filename: "\(filenameStem)-\(UUID().uuidString.prefix(6)).\(fileExtension)",
            mimeType: normalizedMimeType,
            data: rawData,
            pixelWidth: Int(image.size.width),
            pixelHeight: Int(image.size.height)
        )
    }

    static func makeRecordedAudio(
        from rawData: Data,
        suggestedFilename: String?,
        durationSeconds: Double,
        mimeType: String = "audio/aac"
    ) throws -> ChatAttachment {
        guard rawData.isEmpty == false else {
            throw AttachmentProcessingError.unsupportedAudio
        }

        guard rawData.count <= maximumAudioPayloadBytes else {
            throw AttachmentProcessingError.audioTooLarge(maximumBytes: maximumAudioPayloadBytes)
        }

        let normalizedMimeType = mimeType.nonEmptyTrimmed ?? "audio/aac"
        let fileExtension = preferredAudioFileExtension(for: normalizedMimeType)
        let filenameStem = URL(fileURLWithPath: suggestedFilename ?? "voice.\(fileExtension)")
            .deletingPathExtension()
            .lastPathComponent
            .nonEmptyTrimmed ?? "voice"

        return ChatAttachment(
            kind: .audio,
            filename: "\(filenameStem)-\(UUID().uuidString.prefix(6)).\(fileExtension)",
            mimeType: normalizedMimeType,
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

    private static func preferredImageFileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png":
            return "png"
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        default:
            return "img"
        }
    }

    private static func preferredAudioFileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "audio/aac":
            return "aac"
        case "audio/wav", "audio/x-wav":
            return "wav"
        case "audio/flac":
            return "flac"
        case "audio/mp4", "audio/m4a", "audio/x-m4a":
            return "m4a"
        default:
            return "audio"
        }
    }
}

typealias ChatImageAttachment = ChatAttachment

nonisolated struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: ChatRole
    var text: String
    var thoughtSummary: String?
    var modelResponseParts: [GeminiPartPayload]?
    var createdAt: Date
    var attachments: [ChatAttachment]
    var status: ChatMessageStatus

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        thoughtSummary: String? = nil,
        modelResponseParts: [GeminiPartPayload]? = nil,
        createdAt: Date = .now,
        attachments: [ChatAttachment] = [],
        status: ChatMessageStatus = .sent
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thoughtSummary = thoughtSummary
        self.modelResponseParts = modelResponseParts?.isEmpty == true ? nil : modelResponseParts
        self.createdAt = createdAt
        self.attachments = attachments
        self.status = status
    }

    var cleanedText: String {
        recoveredVisibleText.trimmed
    }

    var cleanedThoughtSummary: String? {
        recoveredThoughtSummary?.nonEmptyTrimmed
    }

    var cleanedModelResponseParts: [GeminiPartPayload]? {
        guard let modelResponseParts, modelResponseParts.contains(where: \.hasRecoverableContent) else {
            return nil
        }

        return modelResponseParts
    }

    var hasVisibleContent: Bool {
        cleanedText.isEmpty == false ||
        cleanedThoughtSummary != nil ||
        cleanedModelResponseParts != nil ||
        attachments.isEmpty == false ||
        status == .streaming
    }

    var renderSignature: ChatMessageRenderSignature {
        ChatMessageRenderSignature(
            id: id,
            role: role,
            text: cleanedText,
            thoughtSummary: cleanedThoughtSummary,
            createdAt: createdAt,
            status: status,
            attachments: attachments.map(\.renderSignature)
        )
    }

    private var recoveredVisibleText: String {
        guard role == .assistant,
              let modelResponseParts,
              let visibleText = mergedGeminiText(from: modelResponseParts, includeThoughts: false)
        else {
            return text
        }

        return visibleText
    }

    private var recoveredThoughtSummary: String? {
        guard role == .assistant,
              let modelResponseParts,
              let thoughtText = mergedGeminiText(from: modelResponseParts, includeThoughts: true)
        else {
            return thoughtSummary
        }

        return thoughtText
    }
}

nonisolated enum AssistantMessageTextRenderingMode: Equatable {
    case plain
    case markdown
}

nonisolated enum ConversationHistoryRenderBudget {
    private enum Threshold {
        static let includedTextCharacters = 320
        static let textCharactersPerUnit = 480
        static let includedTextLines = 6
        static let textLinesPerUnit = 12
        static let includedThoughtCharacters = 120
        static let thoughtCharactersPerUnit = 240
        static let markdownPenalty = 2
        static let attachmentPenalty = 4
        static let streamingPenalty = 2
    }

    static func totalCost(in messages: [ChatMessage]) -> Int {
        messages.lazy.reduce(into: 0) { total, message in
            total += cost(of: message)
        }
    }

    static func shouldDeferInitialRendering(
        in messages: [ChatMessage],
        threshold: Int
    ) -> Bool {
        totalCost(in: messages) > threshold
    }

    static func visibleMessageCount(
        in messages: [ChatMessage],
        budget: Int
    ) -> Int {
        guard messages.isEmpty == false else {
            return 0
        }

        let clampedBudget = max(budget, 1)
        let minimumVisibleCount = minimumVisibleCountForLatestExchange(in: messages)
        var accumulatedCost = 0
        var visibleCount = 0

        for message in messages.reversed() {
            let messageCost = cost(of: message)
            if visibleCount >= minimumVisibleCount &&
                accumulatedCost + messageCost > clampedBudget {
                break
            }

            accumulatedCost += messageCost
            visibleCount += 1
        }

        return max(visibleCount, minimumVisibleCount)
    }

    static func lastHiddenMessageID(
        in messages: [ChatMessage],
        budget: Int
    ) -> UUID? {
        let visibleCount = visibleMessageCount(in: messages, budget: budget)
        guard visibleCount < messages.count else {
            return nil
        }

        return messages[messages.count - visibleCount - 1].id
    }

    static func budgetForLoadingOlderMessages(
        in messages: [ChatMessage],
        currentBudget: Int,
        preferredIncrement: Int
    ) -> Int {
        let totalHistoryCost = totalCost(in: messages)
        guard totalHistoryCost > 0 else {
            return 0
        }

        let currentVisibleCount = visibleMessageCount(in: messages, budget: currentBudget)
        guard currentVisibleCount < messages.count else {
            return totalHistoryCost
        }

        let nextVisibleCount = min(messages.count, currentVisibleCount + 1)
        let minimumBudgetToRevealNextMessage = requiredBudgetForLatestMessages(
            in: messages,
            count: nextVisibleCount
        )

        return min(
            totalHistoryCost,
            max(
                max(currentBudget, 1) + max(preferredIncrement, 1),
                minimumBudgetToRevealNextMessage
            )
        )
    }

    private static func cost(of message: ChatMessage) -> Int {
        var cost = 1
        let text = message.cleanedText

        if text.isEmpty == false {
            cost += overflowUnits(
                for: text.count,
                included: Threshold.includedTextCharacters,
                perUnit: Threshold.textCharactersPerUnit
            )
            cost += overflowUnits(
                for: lineCount(in: text),
                included: Threshold.includedTextLines,
                perUnit: Threshold.textLinesPerUnit
            )

            if message.role == .assistant,
               text.preferredAssistantMessageTextRenderingMode == .markdown {
                cost += Threshold.markdownPenalty
            }
        }

        if let thoughtSummary = message.cleanedThoughtSummary {
            cost += overflowUnits(
                for: thoughtSummary.count,
                included: Threshold.includedThoughtCharacters,
                perUnit: Threshold.thoughtCharactersPerUnit
            )
        }

        if message.attachments.isEmpty == false {
            cost += message.attachments.count * Threshold.attachmentPenalty
        }

        if message.status == .streaming {
            cost += Threshold.streamingPenalty
        }

        return max(cost, 1)
    }

    private static func minimumVisibleCountForLatestExchange(in messages: [ChatMessage]) -> Int {
        guard let latestUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            return 1
        }

        return max(messages.count - latestUserIndex, 1)
    }

    private static func overflowUnits(
        for value: Int,
        included: Int,
        perUnit: Int
    ) -> Int {
        guard value > included else {
            return 0
        }

        let overflow = value - included
        return (overflow + perUnit - 1) / perUnit
    }

    private static func lineCount(in text: String) -> Int {
        text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }

    private static func requiredBudgetForLatestMessages(
        in messages: [ChatMessage],
        count: Int
    ) -> Int {
        guard count > 0 else {
            return 0
        }

        return messages.suffix(count).reduce(into: 0) { total, message in
            total += cost(of: message)
        }
    }
}

nonisolated struct ChatAttachmentRenderSignature: Equatable {
    let id: UUID
    let kind: ChatAttachmentKind
    let filename: String
    let mimeType: String
    let blobFilename: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let durationSeconds: Double?
    let sizeInBytes: Int
}

nonisolated struct ChatMessageRenderSignature: Equatable {
    let id: UUID
    let role: ChatRole
    let text: String
    let thoughtSummary: String?
    let createdAt: Date
    let status: ChatMessageStatus
    let attachments: [ChatAttachmentRenderSignature]
}

extension ChatAttachment {
    var renderSignature: ChatAttachmentRenderSignature {
        ChatAttachmentRenderSignature(
            id: id,
            kind: kind,
            filename: filename,
            mimeType: mimeType,
            blobFilename: blobFilename,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            durationSeconds: durationSeconds,
            sizeInBytes: data.count
        )
    }
}

extension String {
    private enum AssistantMessageRenderingThreshold {
        static let maximumMarkdownCharacters = 2_400
        static let maximumMarkdownLines = 48
    }

    var preferredAssistantMessageTextRenderingMode: AssistantMessageTextRenderingMode {
        guard isEmpty == false else {
            return .plain
        }

        let containsMath = containsAssistantRenderableMath

        guard containsMarkdownFormattingHintForAssistantRendering else {
            return .plain
        }

        let lineCount = reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }

        if (count > AssistantMessageRenderingThreshold.maximumMarkdownCharacters ||
            lineCount > AssistantMessageRenderingThreshold.maximumMarkdownLines) &&
            containsMath == false {
            return .plain
        }

        return .markdown
    }

    var containsAssistantRenderableMath: Bool {
        if contains("$$") ||
            contains("\\(") ||
            contains("\\[") ||
            contains("\\begin{equation}") ||
            contains("\\begin{equation*}") {
            return true
        }

        return containsLikelyInlineMathDelimitedByDollar
    }

    fileprivate var containsMarkdownFormattingHintForAssistantRendering: Bool {
        if contains("```") ||
            contains("`") ||
            contains("![") ||
            contains("](") ||
            containsAssistantRenderableMath {
            return true
        }

        return split(separator: "\n", omittingEmptySubsequences: false).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.isEmpty == false else {
                return false
            }

            if line.hasPrefix("# ") ||
                line.hasPrefix("##") ||
                line.hasPrefix("- ") ||
                line.hasPrefix("* ") ||
                line.hasPrefix("> ") {
                return true
            }

            if line.hasPrefix("|") && line.hasSuffix("|") {
                return true
            }

            return line.range(
                of: #"^\d+\.\s+\S"#,
                options: .regularExpression
            ) != nil
        }
    }

    private var containsLikelyInlineMathDelimitedByDollar: Bool {
        var pendingOpeningDollarIndex: String.Index?
        var index = startIndex

        while index < endIndex {
            guard self[index] == "$" else {
                index = self.index(after: index)
                continue
            }

            if index > startIndex,
               self[self.index(before: index)] == "\\" {
                index = self.index(after: index)
                continue
            }

            if let openingDollarIndex = pendingOpeningDollarIndex {
                let contentStart = self.index(after: openingDollarIndex)
                let content = String(self[contentStart..<index])

                if Self.isLikelyInlineMathContent(content) {
                    return true
                }

                pendingOpeningDollarIndex = nil
            } else {
                pendingOpeningDollarIndex = index
            }

            index = self.index(after: index)
        }

        return false
    }

    private static func isLikelyInlineMathContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.contains("\n") == false
        else {
            return false
        }

        let obviousMathTokens = ["\\", "^", "_", "{", "}", "=", "+", "-", "*", "/", "<", ">", "(", ")", "[", "]", "|"]
        if obviousMathTokens.contains(where: { trimmed.contains($0) }) {
            return true
        }

        let containsWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if containsWhitespace {
            return false
        }

        let hasLetter = trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains)
        let hasDigit = trimmed.unicodeScalars.contains(where: CharacterSet.decimalDigits.contains)

        return hasLetter || (hasDigit && trimmed.count <= 8)
    }
}

nonisolated enum AssistantMessageTextRenderingDecider {
    static func expandedMode(for text: String) -> AssistantMessageTextRenderingMode {
        guard text.isEmpty == false,
              text.containsMarkdownFormattingHintForAssistantRendering
        else {
            return .plain
        }

        return .markdown
    }
}

nonisolated struct EmbeddedModelGeneratedImageExtraction: Equatable {
    var text: String
    var attachments: [ChatAttachment]
    var didChange: Bool
}

nonisolated enum AssistantMessageContentNormalizer {
    private static let dataImageMarkdownRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(\s*(data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]+)(?:\s+"[^"]*")?\s*\)"#,
        options: [.caseInsensitive]
    )
    private static let dataImageHTMLRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*\bsrc\s*=\s*(['"])(data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]+)\1[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let trailingDataImageRegex = try! NSRegularExpression(
        pattern: #"data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]+$"#,
        options: [.caseInsensitive]
    )
    private static let trailingMarkdownDataImageRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(\s*data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]*$"#,
        options: [.caseInsensitive]
    )
    private static let trailingHTMLDataImageRegex = try! NSRegularExpression(
        pattern: #"<img\b[^>]*\bsrc\s*=\s*(['"])data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]*$"#,
        options: [.caseInsensitive]
    )
    private static let trailingRawDataImageRegex = try! NSRegularExpression(
        pattern: #"data:image\/[-+.A-Za-z0-9]+;base64,[A-Za-z0-9+\/=\s]*$"#,
        options: [.caseInsensitive]
    )

    static func extractEmbeddedImages(
        from text: String,
        existingAttachments: [ChatAttachment] = [],
        hidesIncompleteTail: Bool = false
    ) -> EmbeddedModelGeneratedImageExtraction {
        guard text.localizedCaseInsensitiveContains("data:image/") else {
            return EmbeddedModelGeneratedImageExtraction(
                text: text,
                attachments: existingAttachments,
                didChange: false
            )
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var mergedAttachments = existingAttachments
        var attachmentKeys = Set(existingAttachments.map(AttachmentDeduplicationKey.init))
        var successfulRanges: [NSRange] = []
        var attachmentsChanged = false
        let completeMatches: [(regex: NSRegularExpression, dataRangeIndex: Int)] = [
            (dataImageMarkdownRegex, 1),
            (dataImageHTMLRegex, 2),
            (trailingDataImageRegex, 0)
        ]

        for (regex, dataRangeIndex) in completeMatches {
            for match in regex.matches(in: text, range: nsRange) {
                let removalRange = match.range(at: 0)
                guard removalRange.location != NSNotFound,
                      successfulRanges.contains(where: { NSIntersectionRange($0, removalRange).length > 0 }) == false,
                      let dataURIRange = Range(match.range(at: dataRangeIndex), in: text),
                      let attachment = makeAttachment(fromDataURI: String(text[dataURIRange]))
                else {
                    continue
                }

                successfulRanges.append(removalRange)

                let deduplicationKey = AttachmentDeduplicationKey(attachment)
                if attachmentKeys.insert(deduplicationKey).inserted {
                    mergedAttachments.append(attachment)
                    attachmentsChanged = true
                }
            }
        }

        var sanitizedText = text
        for range in successfulRanges.sorted(by: { $0.location > $1.location }) {
            guard let stringRange = Range(range, in: sanitizedText) else {
                continue
            }

            sanitizedText.removeSubrange(stringRange)
        }

        if hidesIncompleteTail,
           let trailingFragmentRange = trailingImageFragmentRange(in: sanitizedText) {
            guard let stringRange = Range(trailingFragmentRange, in: sanitizedText) else {
                return EmbeddedModelGeneratedImageExtraction(
                    text: cleanupMarkdownText(afterRemovingImagesFrom: sanitizedText),
                    attachments: mergedAttachments,
                    didChange: attachmentsChanged || sanitizedText != text
                )
            }

            sanitizedText.removeSubrange(stringRange)
        }

        sanitizedText = cleanupMarkdownText(afterRemovingImagesFrom: sanitizedText)

        return EmbeddedModelGeneratedImageExtraction(
            text: sanitizedText,
            attachments: mergedAttachments,
            didChange: attachmentsChanged || sanitizedText != text
        )
    }

    static func normalized(message: ChatMessage) -> ChatMessage {
        guard message.role == .assistant, message.text.isEmpty == false else {
            return message
        }

        let extraction = extractEmbeddedImages(
            from: message.text,
            existingAttachments: message.attachments,
            hidesIncompleteTail: message.status == .streaming
        )
        guard extraction.didChange else {
            return message
        }

        var normalizedMessage = message
        normalizedMessage.text = extraction.text
        normalizedMessage.attachments = extraction.attachments
        // Avoid reusing the original model parts when they contained raw data URIs.
        normalizedMessage.modelResponseParts = nil
        return normalizedMessage
    }

    static func normalized(conversation: ConversationThread) -> (conversation: ConversationThread, didChange: Bool) {
        var normalizedConversation = conversation
        var didChange = false

        for index in normalizedConversation.messages.indices {
            let normalizedMessage = normalized(message: normalizedConversation.messages[index])
            if normalizedMessage != normalizedConversation.messages[index] {
                normalizedConversation.messages[index] = normalizedMessage
                didChange = true
            }
        }

        return (normalizedConversation, didChange)
    }

    private static func cleanupMarkdownText(afterRemovingImagesFrom text: String) -> String {
        let withoutTrailingLineSpaces = text.replacingOccurrences(
            of: #"[ \t]+\n"#,
            with: "\n",
            options: .regularExpression
        )

        return withoutTrailingLineSpaces.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
    }

    private static func trailingImageFragmentRange(in text: String) -> NSRange? {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let trailingMatchers = [
            trailingMarkdownDataImageRegex,
            trailingHTMLDataImageRegex,
            trailingRawDataImageRegex
        ]

        return trailingMatchers
            .compactMap { regex in
                regex.firstMatch(in: text, range: nsRange)?.range(at: 0)
            }
            .filter { $0.location != NSNotFound }
            .min(by: { $0.location < $1.location })
    }

    private static func makeAttachment(fromDataURI dataURI: String) -> ChatAttachment? {
        guard dataURI.hasPrefix("data:") else {
            return nil
        }

        let payload = String(dataURI.dropFirst(5))
        guard let commaIndex = payload.firstIndex(of: ",") else {
            return nil
        }

        let metadata = String(payload[..<commaIndex])
        let encodedPayload = String(payload[payload.index(after: commaIndex)...])
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let metadataComponents = metadata.split(separator: ";", omittingEmptySubsequences: false)
        let mimeType = metadataComponents.first.map(String.init)?.nonEmptyTrimmed
        guard let mimeType,
              mimeType.lowercased().hasPrefix("image/"),
              metadataComponents.contains(where: { $0.caseInsensitiveCompare("base64") == .orderedSame }),
              let rawData = Data(base64Encoded: encodedPayload, options: [.ignoreUnknownCharacters]),
              let attachment = try? ChatAttachment.makeModelGeneratedImage(from: rawData, mimeType: mimeType)
        else {
            return nil
        }

        return attachment
    }

    private struct AttachmentDeduplicationKey: Hashable {
        let mimeType: String
        let data: Data

        init(_ attachment: ChatAttachment) {
            self.mimeType = attachment.mimeType
            self.data = attachment.data
        }
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
        listSummary.previewText
    }

    var messageCount: Int {
        listSummary.messageCount
    }

    var containsAudioAttachments: Bool {
        listSummary.containsAudioAttachments
    }

    var containsImageAttachments: Bool {
        listSummary.containsImageAttachments
    }

    var listSummary: ConversationThreadListSummary {
        ConversationThreadListSummary(conversation: self)
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

    mutating func upsertMessage(
        _ message: ChatMessage,
        updatesTimestamp: Bool = true
    ) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }

        if updatesTimestamp {
            updatedAt = .now
        }
    }

    mutating func removeMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        updatedAt = .now
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
