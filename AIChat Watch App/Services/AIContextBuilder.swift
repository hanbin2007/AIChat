//
//  AIContextBuilder.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum AIContextBuilder {
    static let conciseSystemPrompt =
        """
        You are AIChat on Apple Watch.
        Keep answers clear, concise, and easy to scan on a small screen unless the user explicitly asks for detail.
        If a user turn includes audio attachments, treat the speech in the audio as the user's request and answer it directly instead of only describing or transcribing the audio.
        """

    static func systemPrompt(for configuration: ConversationAIConfiguration) -> String? {
        switch configuration.systemPromptMode {
        case .concise:
            return conciseSystemPrompt
        case .default:
            // Match AI Studio's out-of-box behavior by not sending extra system instructions.
            return nil
        }
    }

    static func selectedMessages(
        from messages: [ChatMessage],
        maxContextMessages: Int,
        maxCharacterBudget: Int,
        maxInlineAttachmentBytes: Int
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
                    consumedImageBytes + imageBytes > maxInlineAttachmentBytes
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

    static func transcriptionContextSummary(
        from messages: [ChatMessage],
        maxContextMessages: Int,
        maxCharacterBudget: Int
    ) -> String? {
        var selectedLines: [String] = []
        var consumedCharacters = 0

        for message in messages.reversed() {
            guard message.status != .failed,
                  message.role != .system,
                  let text = message.cleanedText.nonEmptyTrimmed
            else {
                continue
            }

            let speaker = message.role == .assistant ? "Assistant" : "User"
            let line = "\(speaker): \(text.collapseWhitespace())"
            let lineCost = max(line.count, 24)

            let exceedsBudget =
                selectedLines.isEmpty == false &&
                (
                    selectedLines.count >= maxContextMessages ||
                    consumedCharacters + lineCost > maxCharacterBudget
                )

            if exceedsBudget {
                break
            }

            selectedLines.append(line)
            consumedCharacters += lineCost
        }

        return selectedLines
            .reversed()
            .joined(separator: "\n")
            .nonEmptyTrimmed
    }
}
