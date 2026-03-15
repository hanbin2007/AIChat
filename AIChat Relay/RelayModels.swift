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

struct RelayDebugEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let body: String
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
    case didCompleteRequest(path: String, remoteAddress: String?)
    case didFailRequest(path: String, remoteAddress: String?, statusCode: Int, message: String)
    case debug(title: String, body: String)
    case log(level: RelayLogLevel, message: String)
    case listenerFailed(message: String)
}

struct RelayChatRequest: Decodable, Sendable {
    var model: String?
    var systemPrompt: String?
    var thinkingIntensity: String?
    var maxOutputTokens: Int?
    var includeThoughts: Bool?
    var usesGoogleSearch: Bool?
    var usesCodeExecution: Bool?
    var messages: [RelayMessage]
}

struct RelayMessage: Decodable, Sendable {
    var role: String
    var text: String?
    var modelResponseParts: [GeminiPartPayload]?
    var attachments: [RelayAttachment]
}

struct RelayAttachment: Codable, Sendable {
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

struct RelayMemoryMessage: Codable, Sendable {
    var id: String
    var role: String
    var text: String
}

struct RelayMemoryFocusState: Codable, Sendable {
    var kind: String?
    var title: String?
    var focusNote: String?
    var openLoops: [String]
}

struct RelayMemoryExtractionRequest: Decodable, Sendable {
    var model: String?
    var mode: String
    var conversationTitle: String
    var recentMessages: [RelayMemoryMessage]
    var existingFocusState: RelayMemoryFocusState?
    var existingMemoryItems: [String]
    var archiveCandidateMessages: [RelayMemoryMessage]
}

struct RelayMemoryExtractionResponse: Codable, Sendable {
    var kind: String?
    var title: String?
    var focusNote: String?
    var openLoops: [String]
    var memoryItems: [String]
    var archiveTitle: String?
    var archiveSummary: String?
    var archiveOpenLoops: [String]
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
    case modelResponseParts([GeminiPartPayload])
    case attachment(RelayAttachment)
    case done(String)
    case error(String)

    var eventName: String {
        switch self {
        case .answerDelta:
            return "answer_delta"
        case .thoughtDelta:
            return "thought_delta"
        case .modelResponseParts:
            return "model_content"
        case .attachment:
            return "attachment"
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
            payload = RelaySSEPayload(type: "answer_delta", text: text, parts: nil, message: nil, finishReason: nil, attachment: nil)
        case .thoughtDelta(let text):
            payload = RelaySSEPayload(type: "thought_delta", text: text, parts: nil, message: nil, finishReason: nil, attachment: nil)
        case .modelResponseParts(let parts):
            payload = RelaySSEPayload(type: "model_content", text: nil, parts: parts, message: nil, finishReason: nil, attachment: nil)
        case .attachment(let attachment):
            payload = RelaySSEPayload(type: "attachment", text: nil, parts: nil, message: nil, finishReason: nil, attachment: attachment)
        case .done(let finishReason):
            payload = RelaySSEPayload(type: "done", text: nil, parts: nil, message: nil, finishReason: finishReason, attachment: nil)
        case .error(let message):
            payload = RelaySSEPayload(type: "error", text: nil, parts: nil, message: message, finishReason: nil, attachment: nil)
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
    var parts: [GeminiPartPayload]?
    var message: String?
    var finishReason: String?
    var attachment: RelayAttachment?
}

enum JSONValue: Codable, Equatable, Hashable, Sendable {
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

struct GeminiGenerateContentRequest: Encodable, Sendable {
    var systemInstruction: GeminiContent?
    var contents: [GeminiContent]
    var tools: [GeminiTool]?
    var generationConfig: GeminiGenerationConfig

    init(
        systemInstruction: GeminiContent?,
        contents: [GeminiContent],
        tools: [GeminiTool]? = nil,
        generationConfig: GeminiGenerationConfig
    ) {
        self.systemInstruction = systemInstruction
        self.contents = contents
        self.tools = tools
        self.generationConfig = generationConfig
    }
}

struct GeminiContent: Encodable, Sendable {
    var role: String?
    var parts: [GeminiPartPayload]
}

struct GeminiTool: Encodable, Sendable {
    var googleSearch: GeminiGoogleSearchTool?
    var codeExecution: GeminiCodeExecutionTool?
}

struct GeminiGoogleSearchTool: Encodable, Sendable {}

struct GeminiCodeExecutionTool: Encodable, Sendable {}

struct GeminiPartPayload: Codable, Equatable, Hashable, Sendable {
    private var rawObject: [String: JSONValue]

    init(
        text: String? = nil,
        inlineData: GeminiInlineData? = nil,
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

    var thought: Bool? {
        value(forKeys: "thought")?.boolValue
    }

    var inlineData: GeminiInlineData? {
        guard let object = value(forKeys: "inlineData", "inline_data")?.objectValue,
              let mimeType = object["mimeType"]?.stringValue ?? object["mime_type"]?.stringValue,
              let data = object["data"]?.stringValue
        else {
            return nil
        }

        return GeminiInlineData(mimeType: mimeType, data: data)
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

struct GeminiInlineData: Codable, Sendable {
    var mimeType: String
    var data: String
}

struct GeminiGenerationConfig: Encodable, Sendable {
    var temperature: Double
    var topP: Double
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
    var responseMimeType: String?
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
    var parts: [GeminiPartPayload]?
}

struct GeminiAPIErrorEnvelope: Decodable, Sendable {
    var error: GeminiAPIError
}

struct GeminiAPIError: Decodable, Sendable {
    var message: String
}
