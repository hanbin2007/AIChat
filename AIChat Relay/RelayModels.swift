//
//  RelayModels.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation

enum RelayLogLevel: String, Codable, CaseIterable, Sendable {
    case info
    case success
    case warning
    case error

    var displayName: String {
        switch self {
        case .info:
            return "Info"
        case .success:
            return "Success"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}

enum RelayLogCategory: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case request
    case completed
    case failure
    case billing
    case usage
    case system

    var displayName: String {
        switch self {
        case .lifecycle:
            return "Lifecycle"
        case .request:
            return "Request"
        case .completed:
            return "Completed"
        case .failure:
            return "Failure"
        case .billing:
            return "Billing"
        case .usage:
            return "Usage"
        case .system:
            return "System"
        }
    }
}

/// Structured actor context captured alongside a log or debug entry so that the
/// operator can filter by the downstream identities involved in a relay
/// transaction. All fields are optional because lifecycle / system events have
/// no associated actor.
struct RelayActorContext: Equatable, Sendable, Hashable {
    var accountID: UUID?
    var accountDisplayName: String?
    var accountNote: String?
    var deviceID: String?
    var deviceAlias: String?
    var deviceNote: String?
    var devicePlatform: RelayDevicePlatform?
    var keyID: UUID?
    var keyNote: String?
    var modelID: String?
    var accessSource: RelayAccessSource?

    init(
        accountID: UUID? = nil,
        accountDisplayName: String? = nil,
        accountNote: String? = nil,
        deviceID: String? = nil,
        deviceAlias: String? = nil,
        deviceNote: String? = nil,
        devicePlatform: RelayDevicePlatform? = nil,
        keyID: UUID? = nil,
        keyNote: String? = nil,
        modelID: String? = nil,
        accessSource: RelayAccessSource? = nil
    ) {
        self.accountID = accountID
        self.accountDisplayName = accountDisplayName
        self.accountNote = accountNote
        self.deviceID = deviceID
        self.deviceAlias = deviceAlias
        self.deviceNote = deviceNote
        self.devicePlatform = devicePlatform
        self.keyID = keyID
        self.keyNote = keyNote
        self.modelID = modelID
        self.accessSource = accessSource
    }

    var isEmpty: Bool {
        accountID == nil && deviceID == nil && keyID == nil && modelID == nil
    }

    var accountDisplayTitle: String? {
        if let displayName = RelayContextString.trimmedNonEmpty(accountDisplayName) {
            return displayName
        }
        return accountID.map { "Account " + RelayContextString.shortID($0.uuidString) }
    }

    var deviceDisplayTitle: String? {
        if let alias = RelayContextString.trimmedNonEmpty(deviceAlias) {
            return alias
        }
        return deviceID.map { "Device " + RelayContextString.shortID($0) }
    }

    var keyDisplayTitle: String? {
        if let note = RelayContextString.trimmedNonEmpty(keyNote) {
            return note
        }
        return keyID.map { "Key " + RelayContextString.shortID($0.uuidString) }
    }

    var notesBlob: String {
        [accountNote, deviceNote, keyNote]
            .compactMap { RelayContextString.trimmedNonEmpty($0) }
            .joined(separator: " · ")
    }

    var searchHaystack: String {
        [
            accountID?.uuidString,
            accountDisplayName,
            accountNote,
            deviceID,
            deviceAlias,
            deviceNote,
            devicePlatform?.rawValue,
            keyID?.uuidString,
            keyNote,
            modelID,
            accessSource?.rawValue
        ]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

enum RelayContextString {
    static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func shortID(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: "-", with: "")
        let prefix = sanitized.prefix(8)
        return String(prefix)
    }
}

struct RelayLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: RelayLogLevel
    let category: RelayLogCategory
    let message: String
    let method: String?
    let path: String?
    let remoteAddress: String?
    let statusCode: Int?
    let context: RelayActorContext?

    init(
        timestamp: Date,
        level: RelayLogLevel,
        category: RelayLogCategory = .system,
        message: String,
        method: String? = nil,
        path: String? = nil,
        remoteAddress: String? = nil,
        statusCode: Int? = nil,
        context: RelayActorContext? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.method = method
        self.path = path
        self.remoteAddress = remoteAddress
        self.statusCode = statusCode
        self.context = context
    }
}

enum RelayDebugSource: String, Codable, CaseIterable, Sendable {
    case client
    case relay
    case upstream

    var displayName: String {
        switch self {
        case .client:
            return "Client"
        case .relay:
            return "Relay"
        case .upstream:
            return "Gemini"
        }
    }
}

enum RelayDebugKind: String, Codable, CaseIterable, Sendable {
    case request
    case response
    case event

    var displayName: String {
        rawValue.capitalized
    }
}

struct RelayDebugEvent: Equatable, Sendable {
    let source: RelayDebugSource
    let kind: RelayDebugKind
    let title: String
    let summary: String
    let method: String?
    let path: String?
    let address: String?
    let statusCode: Int?
    let body: String
    var context: RelayActorContext?

    init(
        source: RelayDebugSource,
        kind: RelayDebugKind,
        title: String,
        summary: String,
        method: String?,
        path: String?,
        address: String?,
        statusCode: Int?,
        body: String,
        context: RelayActorContext? = nil
    ) {
        self.source = source
        self.kind = kind
        self.title = title
        self.summary = summary
        self.method = method
        self.path = path
        self.address = address
        self.statusCode = statusCode
        self.body = body
        self.context = context
    }

    func withContext(_ context: RelayActorContext?) -> RelayDebugEvent {
        var copy = self
        copy.context = context
        return copy
    }
}

struct RelayDebugEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let source: RelayDebugSource
    let kind: RelayDebugKind
    let title: String
    let summary: String
    let method: String?
    let path: String?
    let address: String?
    let statusCode: Int?
    let body: String
    let context: RelayActorContext?

    init(
        timestamp: Date,
        source: RelayDebugSource,
        kind: RelayDebugKind,
        title: String,
        summary: String,
        method: String?,
        path: String?,
        address: String?,
        statusCode: Int?,
        body: String,
        context: RelayActorContext? = nil
    ) {
        self.timestamp = timestamp
        self.source = source
        self.kind = kind
        self.title = title
        self.summary = summary
        self.method = method
        self.path = path
        self.address = address
        self.statusCode = statusCode
        self.body = body
        self.context = context
    }
}

struct RelayEndpoint: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let urlString: String
    let detail: String
}

enum RelaySetupStepStatus: Equatable, Sendable {
    case complete
    case pending
    case blocked
}

struct RelaySetupStep: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let detail: String
    let status: RelaySetupStepStatus
}

enum RelayFeedbackStyle: Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

struct RelayActionFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let style: RelayFeedbackStyle
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
    case didReceiveRequest(path: String, method: String?, remoteAddress: String?, context: RelayActorContext?)
    case didCompleteRequest(path: String, method: String?, remoteAddress: String?, context: RelayActorContext?)
    case didFailRequest(
        path: String,
        method: String?,
        remoteAddress: String?,
        statusCode: Int,
        message: String,
        context: RelayActorContext?
    )
    case debug(RelayDebugEvent)
    case log(
        level: RelayLogLevel,
        message: String,
        category: RelayLogCategory,
        method: String?,
        path: String?,
        remoteAddress: String?,
        statusCode: Int?,
        context: RelayActorContext?
    )
    case listenerFailed(message: String)
}

struct RelayChatRequest: Decodable, Sendable {
    var model: String?
    var systemPrompt: String?
    var systemInstructionParts: [GeminiPartPayload]?
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
    case paymentRequired(String)
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
        case .paymentRequired:
            return 402
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
             .paymentRequired(let message),
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
    var safetySettings: [GeminiSafetySetting]?
    var tools: [GeminiTool]?
    var generationConfig: GeminiGenerationConfig

    init(
        systemInstruction: GeminiContent?,
        contents: [GeminiContent],
        safetySettings: [GeminiSafetySetting]? = nil,
        tools: [GeminiTool]? = nil,
        generationConfig: GeminiGenerationConfig
    ) {
        self.systemInstruction = systemInstruction
        self.contents = contents
        self.safetySettings = safetySettings
        self.tools = tools
        self.generationConfig = generationConfig
    }
}

struct GeminiCountTokensRequest: Encodable, Sendable {
    var generateContentRequest: GeminiGenerateContentRequest
}

struct GeminiCountTokensResponse: Decodable, Sendable {
    var totalTokens: Int?
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

    var thoughtSignature: String? {
        value(forKeys: "thoughtSignature", "thought_signature")?.stringValue
    }

    var hasNonSignaturePayload: Bool {
        for (key, value) in rawObject {
            switch key {
            case "thought", "thoughtSignature", "thought_signature":
                continue
            case "text":
                if let text = value.stringValue, text.isEmpty {
                    continue
                }
                return true
            default:
                return true
            }
        }

        return false
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
    var topK: Int?
    var maxOutputTokens: Int
    var thinkingConfig: GeminiThinkingConfig?
    var responseMimeType: String?
    var enableEnhancedCivicAnswers: Bool?
    var mediaResolution: String?
}

struct GeminiThinkingConfig: Encodable, Sendable {
    var thinkingLevel: String?
    var thinkingBudget: Int?
    var includeThoughts: Bool
}

struct GeminiSafetySetting: Encodable, Sendable {
    var category: String
    var threshold: String

    static let aiStudioDefaults: [GeminiSafetySetting] = [
        GeminiSafetySetting(category: "HARM_CATEGORY_HARASSMENT", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_HATE_SPEECH", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "OFF"),
        GeminiSafetySetting(category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "OFF")
    ]
}

struct GeminiStreamChunk: Decodable, Sendable {
    var candidates: [GeminiCandidate]?
    var usageMetadata: GeminiUsageMetadata?
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

struct GeminiUsageMetadata: Decodable, Sendable {
    var promptTokenCount: Int?
    var candidatesTokenCount: Int?
    var thoughtsTokenCount: Int?
    var totalTokenCount: Int?
}

struct RelayUpstreamUsage: Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var thoughtTokens: Int

    var inputTokensOver200k: Bool {
        inputTokens > 200_000
    }

    static func from(_ usageMetadata: GeminiUsageMetadata?) -> RelayUpstreamUsage? {
        guard let usageMetadata else {
            return nil
        }

        let inputTokens = max(0, usageMetadata.promptTokenCount ?? 0)
        let thoughtTokens = max(0, usageMetadata.thoughtsTokenCount ?? 0)
        let explicitOutputTokens = usageMetadata.candidatesTokenCount.map { max(0, $0) }
        let inferredOutputTokens = max(
            0,
            (usageMetadata.totalTokenCount ?? 0) - inputTokens
        )
        let outputTokens = explicitOutputTokens ?? inferredOutputTokens
        let totalTokens = max(0, usageMetadata.totalTokenCount ?? (inputTokens + outputTokens))

        guard inputTokens > 0 || outputTokens > 0 || totalTokens > 0 else {
            return nil
        }

        return RelayUpstreamUsage(
            inputTokens: inputTokens,
            outputTokens: max(outputTokens, inferredOutputTokens),
            totalTokens: max(totalTokens, inputTokens + outputTokens),
            thoughtTokens: thoughtTokens
        )
    }
}
