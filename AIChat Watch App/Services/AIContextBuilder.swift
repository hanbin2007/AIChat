//
//  AIContextBuilder.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum AIContextBuilder {
    static let systemPrompt =
        """
        You are AIChat on Apple Watch.
        Keep answers clear, concise, and easy to scan on a small screen unless the user explicitly asks for detail.
        """

    static func selectedMessages(
        from messages: [ChatMessage],
        maxContextMessages: Int,
        maxCharacterBudget: Int,
        maxInlineImageBytes: Int
    ) -> [ChatMessage] {
        let eligibleMessages = messages.filter { message in
            message.status != .failed &&
            message.role != .system &&
            message.hasVisibleContent
        }

        var selectedMessages: [ChatMessage] = []
        var consumedCharacters = 0
        var consumedImageBytes = 0

        for message in eligibleMessages.reversed() {
            let messageCharacters = max(message.cleanedText.count, 24)
            let imageBytes = message.attachments.reduce(0) { partialResult, attachment in
                partialResult + attachment.sizeInBytes
            }

            let exceedsBudget =
                selectedMessages.isEmpty == false &&
                (
                    selectedMessages.count >= maxContextMessages ||
                    consumedCharacters + messageCharacters > maxCharacterBudget ||
                    consumedImageBytes + imageBytes > maxInlineImageBytes
                )

            if exceedsBudget {
                break
            }

            selectedMessages.append(message)
            consumedCharacters += messageCharacters
            consumedImageBytes += imageBytes
        }

        return selectedMessages.reversed()
    }
}
