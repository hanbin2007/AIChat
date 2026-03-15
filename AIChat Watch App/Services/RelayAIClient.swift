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
            return L10n.tr("error.relay.missing_configuration")
        case .invalidResponse:
            return L10n.tr("error.relay.invalid_response")
        case .remote(let message):
            return message
        case .emptyResponse:
            return L10n.tr("error.relay.empty_response")
        case .incompleteResponse:
            return L10n.tr("error.reply.incomplete")
        case .truncated:
            return L10n.tr("error.reply.truncated")
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

                let delegate = RelayStreamDelegate(
                    continuation: continuation,
                    configuration: configuration
                )
                let streamSession = makeRelayStreamingSession(
                    configuration: configuration,
                    delegate: delegate
                )
                let task = streamSession.dataTask(with: request)
                delegate.attach(task: task, session: streamSession)
                task.resume()

                continuation.onTermination = { _ in
                    delegate.cancel()
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func makeRelayRequest(for conversation: ConversationThread) -> RelayChatRequest {
        let runtimeConfiguration = conversation.resolvedAIConfiguration(defaultModel: configuration.geminiModel)
        let assembledContext = AIContextAssembler.assembleReplyContext(
            for: conversation,
            configuration: runtimeConfiguration
        )
        var relayMessages: [RelayMessage] = []

        if let prefaceText = assembledContext.prefaceText?.nonEmptyTrimmed {
            relayMessages.append(
                RelayMessage(
                    role: ChatRole.user.rawValue,
                    text: prefaceText,
                    modelResponseParts: nil,
                    attachments: []
                )
            )
        }

        relayMessages.append(contentsOf: assembledContext.recentMessages.map { message in
            let modelResponseParts = message.cleanedModelResponseParts
            return RelayMessage(
                role: message.role.rawValue,
                text: modelResponseParts == nil ? requestText(for: message) : nil,
                modelResponseParts: modelResponseParts,
                attachments: modelResponseParts == nil ? message.attachments.map { attachment in
                    RelayAttachment(
                        mimeType: attachment.mimeType,
                        base64Data: attachment.data.base64EncodedString(),
                        filename: attachment.filename
                    )
                } : []
            )
        })

        return RelayChatRequest(
            model: runtimeConfiguration.model,
            systemPrompt: assembledContext.systemPrompt,
            thinkingIntensity: runtimeConfiguration.thinkingIntensity,
            maxOutputTokens: AIModelCatalog.maxOutputTokens(for: runtimeConfiguration.model),
            includeThoughts: true,
            usesGoogleSearch: runtimeConfiguration.usesGoogleSearch,
            usesCodeExecution: runtimeConfiguration.usesCodeExecution,
            messages: relayMessages
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
}

struct RelayTranscriptionService: AITranscriptionService {
    let configuration: AppConfiguration
    var session: URLSession = .shared
    var maxContextMessages: Int = 8
    var maxContextCharacters: Int = 2_400

    func transcribeUserAudio(
        _ audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using transcriptionConfiguration: VoiceTranscriptionConfiguration
    ) async throws -> VoiceTranscriptionResult {
        guard audioAttachment.isAudio else {
            throw VoiceTranscriptionError.invalidAudio
        }

        guard let url = configuration.relayTranscriptionURL,
              let bearerToken = configuration.relayBearerToken
        else {
            throw RelayAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            makeRelayRequest(
                for: audioAttachment,
                in: conversation,
                using: transcriptionConfiguration
            )
        )

        let relaySession = makeRelayURLSession(
            configuration: configuration,
            fallback: session
        )
        let (data, response) = try await relaySession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw relayClientError(from: data)
        }

        return try parseTranscriptionResponse(
            data,
            fallbackModel: transcriptionConfiguration.model
        )
    }

    func parseTranscriptionResponse(
        _ data: Data,
        fallbackModel: String
    ) throws -> VoiceTranscriptionResult {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let transcript: String
        let model: String?

        if let relayResponse = try? decoder.decode(RelayTranscriptionResponse.self, from: data) {
            transcript = relayResponse.text.collapseWhitespace().trimmed
            model = relayResponse.model?.nonEmptyTrimmed
        } else if let rawTranscript = String(data: data, encoding: .utf8)?.nonEmptyTrimmed {
            transcript = rawTranscript
            model = nil
        } else {
            throw RelayAPIError.invalidResponse
        }

        guard transcript.isEmpty == false else {
            throw VoiceTranscriptionError.emptyTranscript
        }

        return VoiceTranscriptionResult(
            text: transcript,
            model: model ?? fallbackModel
        )
    }

    func makeRelayRequest(
        for audioAttachment: ChatAttachment,
        in conversation: ConversationThread,
        using transcriptionConfiguration: VoiceTranscriptionConfiguration
    ) -> RelayTranscriptionRequest {
        RelayTranscriptionRequest(
            model: transcriptionConfiguration.model,
            systemPrompt: VoiceTranscriptionPromptBuilder.systemPrompt,
            prompt: VoiceTranscriptionPromptBuilder.prompt(
                for: conversation,
                customPrompt: transcriptionConfiguration.customPrompt,
                includesContext: transcriptionConfiguration.includesContext,
                existingDraftText: transcriptionConfiguration.existingDraftText,
                maxContextMessages: maxContextMessages,
                maxContextCharacters: maxContextCharacters
            ),
            audio: RelayAttachment(
                mimeType: audioAttachment.mimeType,
                base64Data: audioAttachment.data.base64EncodedString(),
                filename: audioAttachment.filename
            )
        )
    }
}

struct RelayChatRequest: Codable, Equatable {
    var model: String
    var systemPrompt: String?
    var thinkingIntensity: AIThinkingIntensity
    var maxOutputTokens: Int
    var includeThoughts: Bool
    var usesGoogleSearch: Bool
    var usesCodeExecution: Bool
    var messages: [RelayMessage]
}

struct RelayMessage: Codable, Equatable {
    var role: String
    var text: String?
    var modelResponseParts: [GeminiPartPayload]?
    var attachments: [RelayAttachment]
}

struct RelayAttachment: Codable, Equatable {
    var mimeType: String
    var base64Data: String
    var filename: String
}

nonisolated struct RelayStreamEvent: Codable {
    var type: String?
    var text: String?
    var parts: [GeminiPartPayload]?
    var message: String?
    var finishReason: String?
    var attachment: RelayAttachment?
}

nonisolated struct RelayErrorEnvelope: Codable {
    var message: String
}

struct RelayTranscriptionRequest: Codable, Equatable {
    var model: String
    var systemPrompt: String
    var prompt: String
    var audio: RelayAttachment
}

struct RelayTranscriptionResponse: Decodable, Equatable {
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
                    debugDescription: "Expected `text` or `transcript` in relay transcription response."
                )
            )
        }

        self.model = try container.decodeIfPresent(String.self, forKey: .model)
    }
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
        return .remote(message: L10n.format("error.relay.incomplete_finish", normalizedReason))
    }
}

private func relayClientError(from data: Data) -> Error {
    if let envelope = try? JSONDecoder().decode(RelayErrorEnvelope.self, from: data) {
        return RelayAPIError.remote(message: envelope.message)
    }

    return RelayAPIError.invalidResponse
}

func makeRelayURLSession(
    configuration: AppConfiguration,
    fallback: URLSession
) -> URLSession {
    guard configuration.relayAllowsInsecureTLS,
          let allowedHost = configuration.relayBaseURL?.host?.nonEmptyTrimmed
    else {
        return fallback
    }

    let delegate = RelayTLSDelegate(allowedHost: allowedHost)
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.waitsForConnectivity = true
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
}

private func makeRelayStreamingSession(
    configuration: AppConfiguration,
    delegate: RelayStreamDelegate
) -> URLSession {
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.waitsForConnectivity = true
    sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
}

private final class RelayTLSDelegate: NSObject, URLSessionDelegate {
    private let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == allowedHost,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

// URLSession.bytes(for:) ignores the relay trust override for this self-signed tunnel,
// so relay streaming uses a delegate-driven data task and parses SSE incrementally.
private final class RelayStreamDelegate: NSObject, URLSessionDataDelegate {
    private let continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    private let allowsInsecureTLS: Bool
    private let allowedHost: String?
    private let finishLock = NSLock()

    private var didFinish = false
    private var responseStatusCode: Int?
    private var responseBody = Data()
    private var pendingLineData = Data()
    private var currentEvent = "message"
    private var accumulatedText = ""
    private var accumulatedThoughtSummary = ""
    private var latestModelResponseParts: [GeminiPartPayload]?
    private var accumulatedAttachments: [ChatAttachment] = []
    private var didReceiveDoneEvent = false
    private var finishReason: String?
    private weak var task: URLSessionDataTask?
    private weak var session: URLSession?

    init(
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation,
        configuration: AppConfiguration
    ) {
        self.continuation = continuation
        self.allowsInsecureTLS = configuration.relayAllowsInsecureTLS
        self.allowedHost = configuration.relayBaseURL?.host?.nonEmptyTrimmed?.lowercased()
    }

    func attach(task: URLSessionDataTask, session: URLSession) {
        self.task = task
        self.session = session
    }

    func cancel() {
        finishLock.lock()
        let shouldCancel = didFinish == false
        didFinish = true
        finishLock.unlock()

        guard shouldCancel else {
            return
        }

        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowsInsecureTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == allowedHost,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        responseStatusCode = (response as? HTTPURLResponse)?.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard hasFinished == false else {
            return
        }

        if let statusCode = responseStatusCode, (200...299).contains(statusCode) == false {
            responseBody.append(data)
            return
        }

        pendingLineData.append(data)
        consumeBufferedLines()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard hasFinished == false else {
            return
        }

        if let error {
            finish(throwing: error)
            return
        }

        if let statusCode = responseStatusCode, (200...299).contains(statusCode) == false {
            finish(throwing: relayClientError(from: responseBody))
            return
        }

        consumeTrailingLineIfNeeded()

        if let completionError = relayCompletionError(
            didReceiveDoneEvent: didReceiveDoneEvent,
            finishReason: finishReason
        ) {
            finish(throwing: completionError)
            return
        }

        guard accumulatedText.nonEmptyTrimmed != nil || accumulatedAttachments.isEmpty == false else {
            if let latestModelResponseParts, latestModelResponseParts.isEmpty == false {
                continuation.yield(.modelResponseParts(latestModelResponseParts))
                finish()
                return
            }

            finish(throwing: RelayAPIError.emptyResponse)
            return
        }

        if let latestModelResponseParts, latestModelResponseParts.isEmpty == false {
            continuation.yield(.modelResponseParts(latestModelResponseParts))
        }

        finish()
    }

    private var hasFinished: Bool {
        finishLock.lock()
        let finished = didFinish
        finishLock.unlock()
        return finished
    }

    private func finish(throwing error: Error? = nil) {
        finishLock.lock()
        let shouldFinish = didFinish == false
        didFinish = true
        finishLock.unlock()

        guard shouldFinish else {
            return
        }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }

        task?.cancel()
        session?.finishTasksAndInvalidate()
    }

    private func consumeBufferedLines() {
        while let newlineIndex = pendingLineData.firstIndex(of: 0x0A) {
            var lineData = Data(pendingLineData[..<newlineIndex])
            pendingLineData.removeSubrange(...newlineIndex)

            if lineData.last == 0x0D {
                lineData.removeLast()
            }

            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            handleSSELine(line)
        }
    }

    private func consumeTrailingLineIfNeeded() {
        guard pendingLineData.isEmpty == false,
              let line = String(data: pendingLineData, encoding: .utf8)
        else {
            return
        }

        pendingLineData.removeAll(keepingCapacity: false)
        handleSSELine(line)
    }

    private func handleSSELine(_ line: String) {
        let trimmedLine = line.trimmed
        guard trimmedLine.isEmpty == false else {
            return
        }

        if trimmedLine.hasPrefix("event:") {
            currentEvent = String(trimmedLine.dropFirst(6)).trimmed
            return
        }

        guard trimmedLine.hasPrefix("data:") else {
            return
        }

        let dataString = String(trimmedLine.dropFirst(5)).trimmed
        guard let payloadData = dataString.data(using: .utf8),
              let payload = try? JSONDecoder().decode(RelayStreamEvent.self, from: payloadData)
        else {
            return
        }

        switch payload.type ?? currentEvent {
        case "delta", "answer_delta":
            let delta = normalizedDelta(
                chunkText: payload.text ?? "",
                currentText: &accumulatedText
            )
            if let delta, delta.isEmpty == false {
                continuation.yield(.answerDelta(delta))
            }
        case "thought_delta":
            let delta = normalizedDelta(
                chunkText: payload.text ?? "",
                currentText: &accumulatedThoughtSummary
            )
            if let delta, delta.isEmpty == false {
                continuation.yield(.thoughtDelta(delta))
            }
        case "model_content":
            guard let parts = payload.parts, parts.isEmpty == false else {
                break
            }

            latestModelResponseParts = parts
        case "attachment":
            guard let payloadAttachment = payload.attachment,
                  let attachment = modelImageAttachment(from: payloadAttachment),
                  accumulatedAttachments.contains(where: { $0.mimeType == attachment.mimeType && $0.data == attachment.data }) == false
            else {
                break
            }

            accumulatedAttachments.append(attachment)
            continuation.yield(.attachment(attachment))
        case "error":
            finish(throwing: RelayAPIError.remote(message: payload.message ?? "Relay stream failed."))
        case "done":
            didReceiveDoneEvent = true
            if let payloadFinishReason = payload.finishReason?.nonEmptyTrimmed {
                finishReason = payloadFinishReason
            }
        default:
            break
        }
    }
}

private func modelImageAttachment(from relayAttachment: RelayAttachment) -> ChatAttachment? {
    guard let rawData = Data(base64Encoded: relayAttachment.base64Data) else {
        return nil
    }

    return try? ChatAttachment.makeModelGeneratedImage(
        from: rawData,
        mimeType: relayAttachment.mimeType,
        suggestedFilename: relayAttachment.filename
    )
}
