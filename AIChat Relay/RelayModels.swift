//
//  RelayModels.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation

enum RelayLogLevel: String, Codable, Sendable {
    case info
    case success
    case warning
    case error
}

struct RelayLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: RelayLogLevel
    let message: String
}

struct RelayEndpoint: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let urlString: String
    let detail: String
}

enum RelayServerStatus: Equatable {
    case stopped
    case starting
    case running
    case failed(String)
}

enum RelayServerEvent: Sendable {
    case didStart(port: UInt16)
    case didStop
    case didReceiveRequest(path: String, remoteAddress: String?)
    case log(level: RelayLogLevel, message: String)
    case listenerFailed(message: String)
}

struct RelayChatRequest: Decodable, Sendable {
    var model: String?
    var systemPrompt: String?
    var thinkingIntensity: String?
    var maxOutputTokens: Int?
    var includeThoughts: Bool?
    var messages: [RelayMessage]
}

struct RelayMessage: Decodable, Sendable {
    var role: String
    var text: String?
    var attachments: [RelayAttachment]
}

struct RelayAttachment: Decodable, Sendable {
    var mimeType: String
    var base64Data: String
    var filename: String
}

struct RelayTranscriptionRequest: Decodable, Sendable {
    var model: String?
    var systemPrompt: String?
    var prompt: String
    var audio: RelayAttachment
}

struct RelayTranscriptionResponse: Encodable, Sendable {
    var text: String
    var model: String
}

enum RelayHTTPError: LocalizedError, Sendable {
    case badRequest(String)
    case unauthorized
    case missingConfiguration(String)
    case upstream(statusCode: Int, message: String)
    case invalidUpstreamResponse
    case internalError(String)

    var errorDescription: String? {
        message
    }

    var statusCode: Int {
        switch self {
        case .badRequest:
            return 400
        case .unauthorized:
            return 401
        case .missingConfiguration:
            return 503
        case .upstream(let statusCode, _):
            return statusCode
        case .invalidUpstreamResponse, .internalError:
            return 502
        }
    }

    var message: String {
        switch self {
        case .badRequest(let message),
             .missingConfiguration(let message),
             .upstream(_, let message),
             .internalError(let message):
            return message
        case .unauthorized:
            return "Unauthorized relay request."
        case .invalidUpstreamResponse:
            return "Gemini returned an invalid response."
        }
    }
}

struct RelayErrorEnvelope: Encodable, Sendable {
    var message: String
}

enum RelayOutboundEvent: Sendable {
    case answerDelta(String)
    case thoughtDelta(String)
    case done(String)
    case error(String)

    var eventName: String {
        switch self {
        case .answerDelta:
            return "answer_delta"
        case .thoughtDelta:
            return "thought_delta"
        case .done:
            return "done"
        case .error:
            return "error"
        }
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        let payload: RelaySSEPayload

        switch self {
        case .answerDelta(let text):
            payload = RelaySSEPayload(type: "answer_delta", text: text, message: nil, finishReason: nil)
        case .thoughtDelta(let text):
            payload = RelaySSEPayload(type: "thought_delta", text: text, message: nil, finishReason: nil)
        case .done(let finishReason):
            payload = RelaySSEPayload(type: "done", text: nil, message: nil, finishReason: finishReason)
        case .error(let message):
            payload = RelaySSEPayload(type: "error", text: nil, message: message, finishReason: nil)
        }

        let payloadData = try encoder.encode(payload)
        var data = Data("event: \(eventName)\n".utf8)
        data.append(Data("data: ".utf8))
        data.append(payloadData)
        data.append(Data("\n\n".utf8))
        return data
    }
}

private struct RelaySSEPayload: Encodable, Sendable {
    var type: String
    var text: String?
    var message: String?
    var finishReason: String?
}

struct GeminiGenerateContentRequest: Encodable, Sendable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
    var generationConfig: GeminiGenerationConfig
}

struct GeminiContent: Encodable, Sendable {
    var role: String?
    var parts: [GeminiPart]
}

struct GeminiPart: Encodable, Sendable {
    var text: String?
    var inlineData: GeminiInlineData?
}

struct GeminiInlineData: Encodable, Sendable {
    var mimeType: String
    var data: String
}

struct GeminiGenerationConfig: Encodable, Sendable {
    var temperature: Double
    var topP: Double
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
}

struct GeminiThinkingConfig: Encodable, Sendable {
    var thinkingLevel: String?
    var thinkingBudget: Int?
    var includeThoughts: Bool
}

struct GeminiStreamChunk: Decodable, Sendable {
    var candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Decodable, Sendable {
    var content: GeminiChunkContent?
    var finishReason: String?
}

struct GeminiChunkContent: Decodable, Sendable {
    var parts: [GeminiChunkPart]?
}

struct GeminiChunkPart: Decodable, Sendable {
    var text: String?
    var thought: Bool?
}

struct GeminiAPIErrorEnvelope: Decodable, Sendable {
    var error: GeminiAPIError
}

struct GeminiAPIError: Decodable, Sendable {
    var message: String
}
