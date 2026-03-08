//
//  RelayAIClient.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum RelayAPIError: LocalizedError {
    case missingConfiguration
    case invalidResponse
    case remote(message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Relay settings are missing."
        case .invalidResponse:
            return "Relay returned an invalid response."
        case .remote(let message):
            return message
        case .emptyResponse:
            return "Relay returned an empty reply."
        }
    }
}

struct RelayAIClient: AIStreamingService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 12
    var maxCharacterBudget: Int = 12_000
    var maxInlineImageBytes: Int = 1_800_000

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = configuration.relayStreamURL,
                          let bearerToken = configuration.relayBearerToken
                    else {
                        throw RelayAPIError.missingConfiguration
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let encoder = JSONEncoder()
                    encoder.keyEncodingStrategy = .convertToSnakeCase
                    request.httpBody = try encoder.encode(makeRelayRequest(for: conversation.messages))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw RelayAPIError.invalidResponse
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let errorData = try await readAllBytes(from: bytes)
                        throw relayError(from: errorData)
                    }

                    var accumulatedText = ""
                    var currentEvent = "message"

                    for try await line in bytes.lines {
                        let trimmedLine = line.trimmed
                        guard trimmedLine.isEmpty == false else {
                            continue
                        }

                        if trimmedLine.hasPrefix("event:") {
                            currentEvent = String(trimmedLine.dropFirst(6)).trimmed
                            continue
                        }

                        guard trimmedLine.hasPrefix("data:") else {
                            continue
                        }

                        let dataString = String(trimmedLine.dropFirst(5)).trimmed
                        guard let data = dataString.data(using: .utf8) else {
                            continue
                        }

                        let payload = try JSONDecoder().decode(RelayStreamEvent.self, from: data)

                        switch payload.type ?? currentEvent {
                        case "delta":
                            let delta = normalizedDelta(chunkText: payload.text ?? "", currentText: &accumulatedText)
                            if let delta, delta.isEmpty == false {
                                continuation.yield(delta)
                            }
                        case "error":
                            throw RelayAPIError.remote(message: payload.message ?? "Relay stream failed.")
                        case "done":
                            break
                        default:
                            continue
                        }
                    }

                    guard accumulatedText.nonEmptyTrimmed != nil else {
                        throw RelayAPIError.emptyResponse
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func makeRelayRequest(for messages: [ChatMessage]) -> RelayChatRequest {
        let selectedMessages = AIContextBuilder.selectedMessages(
            from: messages,
            maxContextMessages: maxContextMessages,
            maxCharacterBudget: maxCharacterBudget,
            maxInlineImageBytes: maxInlineImageBytes
        )

        return RelayChatRequest(
            model: configuration.geminiModel,
            systemPrompt: AIContextBuilder.systemPrompt,
            messages: selectedMessages.map { message in
                RelayMessage(
                    role: message.role.rawValue,
                    text: message.cleanedText.nonEmptyTrimmed,
                    attachments: message.attachments.map { attachment in
                        RelayAttachment(
                            mimeType: attachment.mimeType,
                            base64Data: attachment.data.base64EncodedString(),
                            filename: attachment.filename
                        )
                    }
                )
            }
        )
    }

    private func relayError(from data: Data) -> Error {
        if let envelope = try? JSONDecoder().decode(RelayErrorEnvelope.self, from: data) {
            return RelayAPIError.remote(message: envelope.message)
        }

        return RelayAPIError.invalidResponse
    }
}

struct RelayChatRequest: Codable, Equatable {
    var model: String
    var systemPrompt: String
    var messages: [RelayMessage]
}

struct RelayMessage: Codable, Equatable {
    var role: String
    var text: String?
    var attachments: [RelayAttachment]
}

struct RelayAttachment: Codable, Equatable {
    var mimeType: String
    var base64Data: String
    var filename: String
}

struct RelayStreamEvent: Codable {
    var type: String?
    var text: String?
    var message: String?
}

struct RelayErrorEnvelope: Codable {
    var message: String
}
