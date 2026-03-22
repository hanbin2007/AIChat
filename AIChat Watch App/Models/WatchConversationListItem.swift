//
//  WatchConversationListItem.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/21.
//

import Foundation

struct WatchConversationListItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let isFavorite: Bool
    let previewText: String
    let messageCount: Int
    let containsAudioAttachments: Bool
    let containsImageAttachments: Bool
    let modelShortLabel: String
    let thinkingShortLabel: String
}

struct ConversationThreadListSummary: Equatable {
    let previewText: String
    let messageCount: Int
    let containsAudioAttachments: Bool
    let containsImageAttachments: Bool

    init(conversation: ConversationThread) {
        var latestVisibleMessage: ChatMessage?
        var visibleMessageCount = 0
        var hasAudioAttachments = false
        var hasImageAttachments = false

        for message in conversation.messages {
            if message.hasVisibleContent {
                visibleMessageCount += 1
                latestVisibleMessage = message
            }

            if hasAudioAttachments == false,
               message.attachments.contains(where: \.isAudio) {
                hasAudioAttachments = true
            }

            if hasImageAttachments == false,
               message.attachments.contains(where: \.isImage) {
                hasImageAttachments = true
            }
        }

        previewText = Self.previewText(for: latestVisibleMessage)
        messageCount = visibleMessageCount
        containsAudioAttachments = hasAudioAttachments
        containsImageAttachments = hasImageAttachments
    }

    private static func previewText(for lastMessage: ChatMessage?) -> String {
        guard let lastMessage else {
            return L10n.tr("conversation.preview.empty")
        }

        if lastMessage.status == .streaming {
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

    private static func attachmentSummary(for attachments: [ChatAttachment]) -> String {
        let imageCount = attachments.filter(\.isImage).count
        let audioCount = attachments.filter(\.isAudio).count

        switch (imageCount, audioCount) {
        case (0, 1):
            return L10n.tr("conversation.attachment.voice.one")
        case (0, let count) where count > 1:
            return L10n.format("conversation.attachment.voice.many", count)
        case (1, 0):
            return L10n.tr("conversation.attachment.image.one")
        case (let count, 0) where count > 1:
            return L10n.format("conversation.attachment.image.many", count)
        default:
            return L10n.format("conversation.attachment.total", attachments.count)
        }
    }
}
