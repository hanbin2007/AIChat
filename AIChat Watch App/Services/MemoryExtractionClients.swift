//
//  MemoryExtractionClients.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/10.
//
//  - `RelayMemoryExtractionClient` is the production implementation
//    that calls the relay's `/api/v1/memory/extract` endpoint.
//  - `GeminiMemoryExtractionClient` is intentionally a stub: the watch
//    app ships in `relay` mode in production, but the
//    `AIBackendMode.direct` enum case is preserved so dev configs that
//    still wire it through `AIServiceFactory.makeMemoryMaintenanceService`
//    keep compiling. Calling it at runtime throws
//    `RelayAPIError.directModeUnsupported`.
//

import Foundation

private enum MemoryExtractionConstants {
    static let maxOutputTokens = 4_096

    static let systemPrompt =
        """
        You maintain compressed conversation memory for AIChat.
        Return strict JSON only. Do not answer the user.
        Prefer concise Chinese phrasing when the source conversation is Chinese.
        Focus on the current discussion focus, stable reusable memory, and an optional archive summary for older context.
        Use this JSON schema exactly:
        {
          "kind": "casual|teaching|task",
          "title": "short title",
          "focusNote": "compact focus note",
          "openLoops": ["pending question or next step"],
          "memoryItems": ["stable reusable memory item"],
          "archiveTitle": "short archive title or null",
          "archiveSummary": "archive summary or null",
          "archiveOpenLoops": ["pending loop from archive"]
        }
        Rules:
        - Return valid JSON with double quotes and no markdown fence.
        - Keep focusNote compact and faithful to the recent turns.
        - memoryItems should contain only stable reusable memory, not ephemeral chatter.
        - If there is no archive candidate, set archiveTitle and archiveSummary to null and archiveOpenLoops to [].
        - Keep openLoops to the unfinished asks or next steps only.
        """
}

private actor RelayMemoryExtractionSupportCache {
    static let shared = RelayMemoryExtractionSupportCache()

    private var unsupportedRelayBaseURLs: Set<String> = []

    func isUnsupported(baseURL: URL) -> Bool {
        unsupportedRelayBaseURLs.contains(cacheKey(for: baseURL))
    }

    func markUnsupported(baseURL: URL) {
        unsupportedRelayBaseURLs.insert(cacheKey(for: baseURL))
    }

    private func cacheKey(for baseURL: URL) -> String {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? baseURL.absoluteString
    }
}

/// Direct-mode (Gemini) memory-extraction stub. The watch ships in
/// relay mode in production; the enum case `AIBackendMode.direct` is
/// preserved so dev wiring keeps compiling, but the implementation is
/// a stub that throws. Replaces the previous direct-call code path
/// that built `URL(string: "...:generateContent")!` with a force-unwrap
/// (also addresses H8 in the watch-services review).
struct GeminiMemoryExtractionClient: AIMemoryExtractionClient {
    let configuration: AppConfiguration
    var session: URLSession = .shared

    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse {
        throw RelayAPIError.directModeUnsupported
    }
}

struct RelayMemoryExtractionClient: AIMemoryExtractionClient {
    let configuration: AppConfiguration
    var session: URLSession = .shared

    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse {
        guard let url = configuration.relayMemoryExtractURL,
              let relayBaseURL = configuration.relayBaseURL,
              let bearerToken = configuration.resolvedRelayBearerToken
        else {
            throw RelayAPIError.missingConfiguration
        }

        // Mixed-version setups are expected while the watch app and relay app are updated separately.
        // If an older relay returns 404 for this endpoint, stop retrying for the same base URL.
        if await RelayMemoryExtractionSupportCache.shared.isUnsupported(baseURL: relayBaseURL) {
            throw RelayAPIError.remote(
                message: "Relay does not support memory extraction yet. Update the relay app."
            )
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        RelayRequestEnricher.attachClientContext(to: &urlRequest)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let relaySession = makeRelayURLSession(
            configuration: configuration,
            fallback: session
        )
        let (data, response) = try await relaySession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let error = relayExtractionError(from: data)
            if httpResponse.statusCode == 404,
               case let RelayAPIError.remote(message) = error,
               message == "Not found." {
                await RelayMemoryExtractionSupportCache.shared.markUnsupported(baseURL: relayBaseURL)
                throw RelayAPIError.remote(
                    message: "Relay does not support memory extraction yet. Update the relay app."
                )
            }

            throw error
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ConversationMemoryExtractionResponse.self, from: data)
    }

    private func relayExtractionError(from data: Data) -> Error {
        if let envelope = try? JSONDecoder().decode(RelayErrorEnvelope.self, from: data) {
            return RelayAPIError.remote(message: envelope.message)
        }

        return RelayAPIError.invalidResponse
    }
}

private func memoryExtractionPrompt(for request: ConversationMemoryExtractionRequest) -> String {
    var sections: [String] = [
        "Mode hint: \(request.mode)",
        "Conversation title: \(request.conversationTitle)"
    ]

    if let existingFocusState = request.existingFocusState {
        var focusLines: [String] = []
        if let kind = existingFocusState.kind?.nonEmptyTrimmed {
            focusLines.append("kind: \(kind)")
        }
        if let title = existingFocusState.title?.nonEmptyTrimmed {
            focusLines.append("title: \(title)")
        }
        if let focusNote = existingFocusState.focusNote?.nonEmptyTrimmed {
            focusLines.append("focusNote: \(focusNote)")
        }
        if existingFocusState.openLoops.isEmpty == false {
            focusLines.append("openLoops: \(existingFocusState.openLoops.joined(separator: " | "))")
        }

        if focusLines.isEmpty == false {
            sections.append("Existing focus state:\n\(focusLines.joined(separator: "\n"))")
        }
    }

    if request.existingMemoryItems.isEmpty == false {
        sections.append(
            "Existing reusable memory:\n" +
            request.existingMemoryItems.map { "- \($0)" }.joined(separator: "\n")
        )
    }

    sections.append(
        "Recent messages (newest last):\n" +
        request.recentMessages.enumerated().map { index, message in
            "[\(index + 1)] \(message.role): \(message.text)"
        }.joined(separator: "\n")
    )

    if request.archiveCandidateMessages.isEmpty == false {
        sections.append(
            "Archive candidate (older stable slice to compress if useful):\n" +
            request.archiveCandidateMessages.enumerated().map { index, message in
                "[\(index + 1)] \(message.role): \(message.text)"
            }.joined(separator: "\n")
        )
    } else {
        sections.append("Archive candidate: none")
    }

    sections.append("Return JSON only.")
    return sections.joined(separator: "\n\n")
}

func decodeMemoryExtractionResponse(
    from text: String
) throws -> ConversationMemoryExtractionResponse {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let trimmed = text.trimmed
    if let data = trimmed.data(using: .utf8),
       let response = try? decoder.decode(ConversationMemoryExtractionResponse.self, from: data) {
        return response
    }

    // Walk the string for the first balanced JSON object. The previous
    // greedy regex `\{[\s\S]*\}` swallowed everything between the first
    // `{` and the last `}`, breaking decode whenever the model emitted
    // multiple JSON-like blobs (L2 in the watch-services review).
    if let firstObjectSubstring = firstBalancedJSONObject(in: trimmed),
       let data = String(firstObjectSubstring).data(using: .utf8) {
        return try decoder.decode(ConversationMemoryExtractionResponse.self, from: data)
    }

    throw RelayAPIError.invalidResponse
}

/// Returns the substring containing the first top-level balanced
/// `{...}` JSON object in `source`, respecting strings and escaped
/// quotes. Returns `nil` if no balanced object is found.
///
/// Internal so `MemoryExtractionRegexTests` can target this helper
/// directly without round-tripping through `decodeMemoryExtractionResponse`.
func firstBalancedJSONObject(in source: String) -> Substring? {
    var depth = 0
    var startIndex: String.Index?
    var inString = false
    var isEscaped = false

    for index in source.indices {
        let character = source[index]

        if inString {
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                inString = false
            }
            continue
        }

        switch character {
        case "\"":
            inString = true
        case "{":
            if depth == 0 {
                startIndex = index
            }
            depth += 1
        case "}":
            guard depth > 0 else {
                continue
            }
            depth -= 1
            if depth == 0, let startIndex {
                let endIndex = source.index(after: index)
                return source[startIndex..<endIndex]
            }
        default:
            break
        }
    }

    return nil
}
