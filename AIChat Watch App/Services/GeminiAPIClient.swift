//
//  GeminiAPIClient.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

protocol AIChatService {
    func generateReply(for conversation: ConversationThread) async throws -> String
}

enum GeminiAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case api(message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key is missing."
        case .invalidResponse:
            return "Gemini returned an invalid response."
        case .api(let message):
            return message
        case .emptyResponse:
            return "Gemini returned an empty reply."
        }
    }
}

struct GeminiAPIClient: AIChatService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 12
    var maxCharacterBudget: Int = 12_000
    var maxInlineImageBytes: Int = 1_800_000

    func generateReply(for conversation: ConversationThread) async throws -> String {
        guard let apiKey = configuration.geminiAPIKey else {
            throw GeminiAPIError.missingAPIKey
        }

        let requestBody = makeRequestBody(for: conversation.messages)
        var request = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.geminiModel):generateContent?key=\(apiKey)"
            )!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if (200...299).contains(httpResponse.statusCode) == false {
            if let apiError = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
                throw GeminiAPIError.api(message: apiError.error.message)
            }

            throw GeminiAPIError.invalidResponse
        }

        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: data)
        let reply = responseEnvelope.candidates
            .compactMap { candidate in
                candidate.content?.parts
                    .compactMap(\.text)
                    .map { $0.trimmed }
                    .filter { $0.isEmpty == false }
                    .joined(separator: "\n")
                    .nonEmptyTrimmed
            }
            .first

        guard let reply else {
            throw GeminiAPIError.emptyResponse
        }

        return reply
    }

    func makeRequestBody(for messages: [ChatMessage]) -> GeminiGenerateContentRequest {
        GeminiGenerateContentRequest(
            systemInstruction: GeminiContent.systemPrompt(
                """
                You are AIChat on Apple Watch.
                Keep answers clear, concise, and easy to scan on a small screen unless the user explicitly asks for detail.
                """
            ),
            contents: contextWindow(from: messages),
            generationConfig: GeminiGenerationConfig(
                temperature: 0.7,
                topP: 0.9,
                maxOutputTokens: 512
            )
        )
    }

    func contextWindow(from messages: [ChatMessage]) -> [GeminiContent] {
        let eligibleMessages = messages.filter { message in
            message.status == .sent &&
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

        return selectedMessages
            .reversed()
            .compactMap { message in
                guard let role = message.role.geminiRole else {
                    return nil
                }

                var parts = message.attachments.map { attachment in
                    GeminiPart(
                        text: nil,
                        inlineData: GeminiInlineData(
                            mimeType: attachment.mimeType,
                            data: attachment.data.base64EncodedString()
                        )
                    )
                }

                if let text = message.cleanedText.nonEmptyTrimmed {
                    parts.insert(GeminiPart(text: text, inlineData: nil), at: 0)
                }

                return GeminiContent(role: role, parts: parts)
            }
    }
}

struct GeminiGenerateContentRequest: Encodable {
    var systemInstruction: GeminiContent
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

struct GeminiGenerationConfig: Codable, Equatable {
    var temperature: Double
    var topP: Double
    var maxOutputTokens: Int
}

struct GeminiContent: Codable, Equatable {
    var role: String?
    var parts: [GeminiPart]

    static func systemPrompt(_ text: String) -> GeminiContent {
        GeminiContent(role: nil, parts: [GeminiPart(text: text, inlineData: nil)])
    }
}

struct GeminiPart: Codable, Equatable {
    var text: String?
    var inlineData: GeminiInlineData?
}

struct GeminiInlineData: Codable, Equatable {
    var mimeType: String
    var data: String
}

struct GeminiGenerateContentResponse: Decodable {
    var candidates: [GeminiCandidate]
}

struct GeminiCandidate: Decodable {
    var content: GeminiContent?
}

struct GeminiAPIErrorEnvelope: Decodable {
    var error: GeminiAPIErrorMessage
}

struct GeminiAPIErrorMessage: Decodable {
    var message: String
}
