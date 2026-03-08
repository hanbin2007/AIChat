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

nonisolated enum AttachmentProcessingError: LocalizedError {
    case unsupportedImage
    case imageTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "这张图片无法在 Apple Watch 上解析。"
        case .imageTooLarge(let maximumBytes):
            let megabytes = Double(maximumBytes) / 1_000_000
            return "图片过大，请换一张小于 \(String(format: "%.1f", megabytes)) MB 的图片。"
        }
    }
}

nonisolated struct ChatImageAttachment: Identifiable, Codable, Hashable {
    static let maximumPayloadBytes = 1_500_000

    let id: UUID
    var filename: String
    var mimeType: String
    var data: Data
    var pixelWidth: Int
    var pixelHeight: Int

    init(
        id: UUID = UUID(),
        filename: String,
        mimeType: String,
        data: Data,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var previewImage: UIImage? {
        UIImage(data: data)
    }

    var sizeInBytes: Int {
        data.count
    }

    static func makeNormalized(from rawData: Data, suggestedFilename: String?) throws -> ChatImageAttachment {
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
                if jpegData.count <= maximumPayloadBytes {
                    break
                }
            }
        }

        guard normalizedData.count <= maximumPayloadBytes else {
            throw AttachmentProcessingError.imageTooLarge(maximumBytes: maximumPayloadBytes)
        }

        return ChatImageAttachment(
            filename: "\(filenameStem)-\(UUID().uuidString.prefix(6)).jpg",
            mimeType: "image/jpeg",
            data: normalizedData,
            pixelWidth: Int(image.size.width),
            pixelHeight: Int(image.size.height)
        )
    }
}

nonisolated struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: ChatRole
    var text: String
    var createdAt: Date
    var attachments: [ChatImageAttachment]
    var status: ChatMessageStatus

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        createdAt: Date = .now,
        attachments: [ChatImageAttachment] = [],
        status: ChatMessageStatus = .sent
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
        self.status = status
    }

    var cleanedText: String {
        text.trimmed
    }

    var hasVisibleContent: Bool {
        cleanedText.isEmpty == false || attachments.isEmpty == false || status == .streaming
    }
}

nonisolated struct ConversationThread: Identifiable, Codable, Hashable {
    static let untitledTitle = "New Chat"

    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String = ConversationThread.untitledTitle,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    static func empty(now: Date = .now) -> ConversationThread {
        ConversationThread(createdAt: now, updatedAt: now)
    }

    var previewText: String {
        guard let lastMessage = messages.last(where: \.hasVisibleContent) else {
            return "Tap to start a conversation"
        }

        if lastMessage.status == .streaming, lastMessage.cleanedText.isEmpty {
            return "Streaming response..."
        }

        if lastMessage.status == .failed, lastMessage.cleanedText.isEmpty {
            return "Last reply failed"
        }

        if let text = lastMessage.cleanedText.nonEmptyTrimmed {
            return text
        }

        let count = lastMessage.attachments.count
        return count == 1 ? "1 image attached" : "\(count) images attached"
    }

    var messageCount: Int {
        messages.filter(\.hasVisibleContent).count
    }

    mutating func append(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = max(updatedAt, message.createdAt)

        if title == Self.untitledTitle, message.role == .user, let suggested = Self.suggestedTitle(from: message.text) {
            title = suggested
        }
    }

    static func suggestedTitle(from text: String) -> String? {
        let collapsed = text.collapseWhitespace().nonEmptyTrimmed
        guard let collapsed else {
            return nil
        }

        let limit = 26
        guard collapsed.count > limit else {
            return collapsed
        }

        let truncated = String(collapsed.prefix(limit)).trimmed
        return truncated.isEmpty ? nil : "\(truncated)..."
    }

    mutating func clearMessages() {
        messages.removeAll()
        updatedAt = .now
    }

    mutating func updateTitle(_ newTitle: String) {
        title = newTitle.nonEmptyTrimmed ?? Self.untitledTitle
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
