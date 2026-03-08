//
//  RelayAIClient.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

enum RelayAPIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidResponse
    case remote(message: String)
    case emptyResponse
    case incompleteResponse
    case truncated

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
        case .incompleteResponse:
            return "Reply was interrupted before completion."
        case .truncated:
            return "Reply hit the output limit before completion. Send a follow-up to continue."
        }
    }
}

struct RelayAIClient: AIStreamingService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 12
    var maxCharacterBudget: Int = 12_000
    var maxInlineAttachmentBytes: Int = 4_000_000

    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
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
                    request.httpBody = try encoder.encode(makeRelayRequest(for: conversation))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw RelayAPIError.invalidResponse
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let errorData = try await readAllBytes(from: bytes)
                        throw relayError(from: errorData)
                    }

                    var accumulatedText = ""
                    var accumulatedThoughtSummary = ""
                    var currentEvent = "message"
                    var didReceiveDoneEvent = false
                    var finishReason: String?

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
                        case "delta", "answer_delta":
                            let delta = normalizedDelta(chunkText: payload.text ?? "", currentText: &accumulatedText)
                            if let delta, delta.isEmpty == false {
                                continuation.yield(.answerDelta(delta))
                            }
                        case "thought_delta":
                            let delta = normalizedDelta(chunkText: payload.text ?? "", currentText: &accumulatedThoughtSummary)
                            if let delta, delta.isEmpty == false {
                                continuation.yield(.thoughtDelta(delta))
                            }
                        case "error":
                            throw RelayAPIError.remote(message: payload.message ?? "Relay stream failed.")
                        case "done":
                            didReceiveDoneEvent = true
                            if let payloadFinishReason = payload.finishReason?.nonEmptyTrimmed {
                                finishReason = payloadFinishReason
                            }
                        default:
                            continue
                        }
                    }

                    if let completionError = relayCompletionError(
                        didReceiveDoneEvent: didReceiveDoneEvent,
                        finishReason: finishReason
                    ) {
                        throw completionError
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

    func makeRelayRequest(for conversation: ConversationThread) -> RelayChatRequest {
        let runtimeConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        let selectedMessages = AIContextBuilder.selectedMessages(
            from: conversation.messages,
            maxContextMessages: maxContextMessages,
            maxCharacterBudget: maxCharacterBudget,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes
        )

        return RelayChatRequest(
            model: runtimeConfiguration.model,
            systemPrompt: AIContextBuilder.systemPrompt(for: runtimeConfiguration),
            thinkingIntensity: runtimeConfiguration.thinkingIntensity,
            maxOutputTokens: AIModelCatalog.maxOutputTokens(for: runtimeConfiguration.model),
            includeThoughts: true,
            messages: selectedMessages.map { message in
                RelayMessage(
                    role: message.role.rawValue,
                    text: requestText(for: message),
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

    private func requestText(for message: ChatMessage) -> String? {
        if let text = message.cleanedText.nonEmptyTrimmed {
            return text
        }

        guard message.role == .user, message.attachments.contains(where: \.isAudio) else {
            return nil
        }

        return "Listen to the attached audio, infer the user's request, and answer it directly."
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
    var systemPrompt: String?
    var thinkingIntensity: AIThinkingIntensity
    var maxOutputTokens: Int
    var includeThoughts: Bool
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
    var finishReason: String?
}

struct RelayErrorEnvelope: Codable {
    var message: String
}

func relayCompletionError(
    didReceiveDoneEvent: Bool,
    finishReason: String?
) -> RelayAPIError? {
    guard didReceiveDoneEvent else {
        return .incompleteResponse
    }

    guard let normalizedReason = finishReason?.trimmed.nonEmptyTrimmed?.uppercased() else {
        return .incompleteResponse
    }

    switch normalizedReason {
    case "STOP":
        return nil
    case "MAX_TOKENS":
        return .truncated
    default:
        return .remote(message: "Relay reported an incomplete finish (\(normalizedReason)).")
    }
}
