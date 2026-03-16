//
//  MemoryExtractionClients.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/10.
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

struct GeminiMemoryExtractionClient: AIMemoryExtractionClient {
    let configuration: AppConfiguration
    var session: URLSession = .shared

    func extractMemory(
        request: ConversationMemoryExtractionRequest
    ) async throws -> ConversationMemoryExtractionResponse {
        guard let apiKey = configuration.geminiAPIKey else {
            throw GeminiAPIError.missingAPIKey
        }

        var urlRequest = URLRequest(
            url: URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):generateContent"
            )!
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(
            GeminiGenerateContentRequest(
                systemInstruction: GeminiContent.systemPrompt(MemoryExtractionConstants.systemPrompt),
                contents: [
                    GeminiContent(
                        role: "user",
                        parts: [
                            GeminiPart(
                                text: memoryExtractionPrompt(for: request),
                                inlineData: nil
                            )
                        ]
                    )
                ],
                generationConfig: GeminiGenerationConfig(
                    temperature: 0.1,
                    topP: 0.9,
                    topK: nil,
                    maxOutputTokens: MemoryExtractionConstants.maxOutputTokens,
                    thinkingConfig: nil,
                    responseMimeType: "application/json",
                    enableEnhancedCivicAnswers: nil,
                    mediaResolution: nil
                )
            )
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw geminiExtractionError(from: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responseEnvelope = try decoder.decode(GeminiGenerateContentResponse.self, from: data)

        if let completionError = geminiCompletionError(
            for: responseEnvelope.candidates.compactMap(\.finishReason).first
        ) {
            throw completionError
        }

        let text = responseEnvelope.candidates
            .compactMap { $0.content?.parts.compactMap(\.text).joined(separator: "\n") }
            .first?
            .trimmed ?? ""

        return try decodeMemoryExtractionResponse(from: text)
    }

    private func geminiExtractionError(from data: Data) -> Error {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let envelope = try? decoder.decode(GeminiAPIErrorEnvelope.self, from: data) {
            return GeminiAPIError.api(message: envelope.error.message)
        }

        return GeminiAPIError.invalidResponse
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
              let bearerToken = configuration.relayBearerToken
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

private func decodeMemoryExtractionResponse(
    from text: String
) throws -> ConversationMemoryExtractionResponse {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let trimmed = text.trimmed
    if let data = trimmed.data(using: .utf8),
       let response = try? decoder.decode(ConversationMemoryExtractionResponse.self, from: data) {
        return response
    }

    if let range = trimmed.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
       let data = String(trimmed[range]).data(using: .utf8) {
        return try decoder.decode(ConversationMemoryExtractionResponse.self, from: data)
    }

    throw GeminiAPIError.invalidResponse
}
