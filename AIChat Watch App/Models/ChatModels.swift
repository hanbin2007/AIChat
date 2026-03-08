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

nonisolated enum AISystemPromptMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case concise
    case `default`

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .concise:
            return "简洁"
        case .default:
            return "默认"
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
            return "Fast"
        case .balanced:
            return "Balanced"
        case .deep:
            return "Deep"
        case .extreme:
            return "Extreme"
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

    private enum CodingKeys: String, CodingKey {
        case model
        case thinkingIntensity
        case systemPromptMode
    }

    init(
        model: String,
        thinkingIntensity: AIThinkingIntensity = .balanced,
        systemPromptMode: AISystemPromptMode = .concise
    ) {
        self.model = model
        self.thinkingIntensity = thinkingIntensity
        self.systemPromptMode = systemPromptMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decode(String.self, forKey: .model)
        self.thinkingIntensity = try container.decodeIfPresent(AIThinkingIntensity.self, forKey: .thinkingIntensity) ?? .balanced
        self.systemPromptMode = try container.decodeIfPresent(AISystemPromptMode.self, forKey: .systemPromptMode) ?? .concise
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(thinkingIntensity, forKey: .thinkingIntensity)
        try container.encode(systemPromptMode, forKey: .systemPromptMode)
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
            return "这张图片无法在 Apple Watch 上解析。"
        case .unsupportedAudio:
            return "录音文件无法处理，请重试。"
        case .imageTooLarge(let maximumBytes):
            let megabytes = Double(maximumBytes) / 1_000_000
            return "图片过大，请换一张小于 \(String(format: "%.1f", megabytes)) MB 的图片。"
        case .audioTooLarge(let maximumBytes):
            let megabytes = Double(maximumBytes) / 1_000_000
            return "录音过长，请控制在 \(String(format: "%.1f", megabytes)) MB 以内。"
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
    var pixelWidth: Int?
    var pixelHeight: Int?
    var durationSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case filename
        case mimeType
        case data
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
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
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
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
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
            return "Image"
        case .audio:
            return "Voice"
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
    static let untitledTitle = "New Chat"

    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var aiConfiguration: ConversationAIConfiguration?

    init(
        id: UUID = UUID(),
        title: String = ConversationThread.untitledTitle,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessage] = [],
        aiConfiguration: ConversationAIConfiguration? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.aiConfiguration = aiConfiguration
    }

    static func empty(now: Date = .now) -> ConversationThread {
        ConversationThread(createdAt: now, updatedAt: now)
    }

    var previewText: String {
        guard let lastMessage = messages.last(where: \.hasVisibleContent) else {
            return "Tap to start a conversation"
        }

        if lastMessage.status == .streaming, lastMessage.cleanedText.isEmpty {
            if let thoughtSummary = lastMessage.cleanedThoughtSummary {
                return "Thinking: \(thoughtSummary)"
            }
            return "Streaming response..."
        }

        if lastMessage.status == .failed, lastMessage.cleanedText.isEmpty {
            return "Last reply failed"
        }

        if let text = lastMessage.cleanedText.nonEmptyTrimmed {
            return text
        }

        if let thoughtSummary = lastMessage.cleanedThoughtSummary {
            return thoughtSummary
        }

        return attachmentSummary(for: lastMessage.attachments)
    }

    var messageCount: Int {
        messages.filter(\.hasVisibleContent).count
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = max(updatedAt, message.createdAt)

        if title == Self.untitledTitle,
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
            return "Voice message"
        }

        if attachments.contains(where: \.isImage) {
            return "Photo prompt"
        }

        return nil
    }

    mutating func clearMessages() {
        messages.removeAll()
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
            return "1 voice note attached"
        case (0, let audioCount) where audioCount > 1:
            return "\(audioCount) voice notes attached"
        case (1, 0):
            return "1 image attached"
        case (let imageCount, 0) where imageCount > 1:
            return "\(imageCount) images attached"
        default:
            return "\(attachments.count) attachments"
        }
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
}

nonisolated extension ConversationThread {
    func resolvedAIConfiguration(defaultModel: String) -> ConversationAIConfiguration {
        if let aiConfiguration {
            return aiConfiguration
        }

        return ConversationAIConfiguration(model: defaultModel)
    }
}
