//
//  RelayChatDTO.swift
//  AIChat Watch App
//
//  Wire DTOs for the Next.js relay's `/v1/chat/stream`,
//  `/v1/audio/transcribe`, and `/v1/memory/extract` endpoints, plus the
//  domain event enum yielded by the streaming session.
//
//  These types are intentionally distinct from the legacy ones in
//  `Services/RelayAIClient.swift` — the old file's `RelayChatRequest`
//  / `RelayMessage` / `RelayAttachment` / `RelayStreamEvent` etc. will
//  be removed once every caller has been migrated to the new
//  `RelayAPIClient` actor. Until then the new types use a `Stream`
//  prefix to keep the build unambiguous.
//
//  Wire format: every field is camelCase. The relay accepts both
//  camelCase and snake_case but we send canonical camelCase so the
//  request shape is unambiguous.
//

import Foundation

struct RelayStreamRequest: Codable, Equatable, Sendable {
    var model: String
    var systemPrompt: String?
    var systemInstructionParts: [GeminiPartPayload]?
    var thinkingIntensity: AIThinkingIntensity
    var maxOutputTokens: Int
    var includeThoughts: Bool
    var usesGoogleSearch: Bool
    var usesCodeExecution: Bool
    var messages: [RelayStreamMessage]
}

struct RelayStreamMessage: Codable, Equatable, Sendable {
    var role: String
    var text: String?
    var modelResponseParts: [GeminiPartPayload]?
    var attachments: [RelayStreamAttachment]
}

struct RelayStreamAttachment: Codable, Equatable, Sendable {
    var mimeType: String
    var base64Data: String
    var filename: String
}

/// Decoded payload of an SSE `data:` JSON object on `/v1/chat/stream`.
/// The relay always sets `type` explicitly; we still honour the SSE
/// `event:` line as a fallback.
struct RelayStreamFrame: Decodable, Sendable {
    var type: String?
    var text: String?
    var parts: [GeminiPartPayload]?
    var message: String?
    var finishReason: String?
    var attachment: RelayStreamAttachment?
}

/// Domain event emitted by `ChatStreamSession`. The legacy `delta` SSE
/// synonym is intentionally not represented here; only the canonical
/// Next.js relay event names are surfaced to consumers.
enum RelayChatEvent: Equatable, Sendable {
    case answerDelta(String)
    case thoughtDelta(String)
    case modelContent([GeminiPartPayload])
    case attachment(RelayStreamAttachment)
    case done(finishReason: String?)
    case errorEvent(String)
}

struct RelayTranscribeRequest: Codable, Equatable, Sendable {
    var model: String
    var systemPrompt: String
    var prompt: String
    var audio: RelayStreamAttachment
}

struct RelayTranscribeResponse: Decodable, Equatable, Sendable {
    var text: String
    var model: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case transcript
        case model
    }

    init(text: String, model: String?) {
        self.text = text
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self.text = text
        } else if let transcript = try container.decodeIfPresent(String.self, forKey: .transcript) {
            self.text = transcript
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.text,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected `text` or `transcript` in transcription response."
                )
            )
        }
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
    }
}

struct RelayMemoryExtractRequest: Codable, Equatable, Sendable {
    var model: String
    var mode: String
    var conversationTitle: String?
    var existingFocusState: RelayMemoryFocusState?
    var existingMemoryItems: [String]
    var recentMessages: [RelayMemoryMessage]
    var archiveCandidateMessages: [RelayMemoryMessage]
}

struct RelayMemoryFocusState: Codable, Equatable, Sendable {
    var kind: String
    var title: String?
    var focusNote: String?
    var openLoops: [String]
}

struct RelayMemoryMessage: Codable, Equatable, Sendable {
    var role: String
    var text: String
}

struct RelayMemoryExtractResponse: Decodable, Equatable, Sendable {
    var kind: String?
    var title: String?
    var focusNote: String?
    var openLoops: [String]?
    var memoryItems: [String]?
    var archiveTitle: String?
    var archiveSummary: String?
    var archiveOpenLoops: [String]?
}

struct RelayHealthResponse: Decodable, Equatable, Sendable {
    var status: String?
    var version: String?
}
