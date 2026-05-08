//
//  ChatService.swift
//  AIChat Watch App
//
//  Owns one assistant-reply turn end-to-end:
//    1. Append the user message + a streaming-placeholder assistant
//       message to the conversation
//    2. Persist immediately so the conversation list updates
//    3. Open a relay SSE stream via `RelayAPIClient.streamChat`
//    4. Mutate the placeholder assistant message as `answer_delta` /
//       `thought_delta` / `model_content` events arrive
//    5. Persist the final state on `done` / error
//
//  ViewModels consume `send(...)`'s `AsyncThrowingStream<ConversationThread, Error>`
//  and rebind their state to each yielded snapshot. The throwing
//  surface lets a 402 / network error surface as a `RelayClientError`
//  the VM can pattern-match for low-balance CTAs / retry UX.
//
//  Context assembly is delegated to the existing `AIContextAssembler`
//  (kept as the canonical reply-context builder — it's well-tested and
//  unchanged by the relay rewrite).
//

import Foundation

actor ChatService {
    private let api: RelayAPIClient
    private let persistence: ConversationPersistence
    private let defaultModel: String

    init(api: RelayAPIClient, persistence: ConversationPersistence, defaultModel: String) {
        self.api = api
        self.persistence = persistence
        self.defaultModel = defaultModel
    }

    /// Streams one user→assistant turn. Every yielded `ConversationThread`
    /// is a fresh snapshot containing the latest assistant text /
    /// thought summary. The stream finishes on `done` or throws on
    /// transport / 4xx / 5xx errors (see `RelayClientError`).
    nonisolated func send(
        userText: String,
        attachments: [ChatAttachment],
        to conversation: ConversationThread
    ) -> AsyncThrowingStream<ConversationThread, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var thread = conversation

                    // 1. Append user message + assistant placeholder.
                    let userMessage = ChatMessage(
                        role: .user,
                        text: userText,
                        attachments: attachments,
                        status: .sent
                    )
                    var assistant = ChatMessage(
                        role: .assistant,
                        text: "",
                        thoughtSummary: nil,
                        modelResponseParts: nil,
                        status: .streaming
                    )
                    thread.messages.append(userMessage)
                    thread.messages.append(assistant)
                    thread.updatedAt = Date()

                    // 2. Persist + emit so the UI shows the user bubble
                    // and the streaming placeholder immediately.
                    thread = try await self.persist(thread)
                    continuation.yield(thread)

                    // 3. Build the relay request.
                    let runtime = thread.resolvedAIConfiguration(defaultModel: self.defaultModel)
                    let payload = self.buildStreamRequest(thread: thread, runtime: runtime)

                    // 4. Stream and accumulate.
                    var answerText = ""
                    var thoughtText = ""
                    var modelParts: [GeminiPartPayload] = []

                    let stream = await self.api.streamChat(payload, conversationID: thread.id)
                    for try await event in stream {
                        if Task.isCancelled { break }
                        switch event {
                        case .answerDelta(let delta):
                            answerText += delta
                            assistant.text = answerText
                            if !thoughtText.isEmpty { assistant.thoughtSummary = thoughtText }
                            thread = try await self.replaceLastAssistant(in: thread, with: assistant)
                            continuation.yield(thread)
                        case .thoughtDelta(let delta):
                            thoughtText += delta
                            assistant.thoughtSummary = thoughtText
                            thread = try await self.replaceLastAssistant(in: thread, with: assistant)
                            continuation.yield(thread)
                        case .modelContent(let parts):
                            modelParts.append(contentsOf: parts)
                            assistant.modelResponseParts = modelParts
                            thread = try await self.replaceLastAssistant(in: thread, with: assistant)
                            continuation.yield(thread)
                        case .attachment:
                            // Inline attachments returned by the model
                            // (e.g. tool images) are handled in
                            // `model_content` parts already; the bare
                            // `attachment` event is currently advisory.
                            break
                        case .errorEvent(let message):
                            throw RelayClientError.remote(message: message)
                        case .done:
                            assistant.status = .sent
                            if assistant.text.isEmpty, !thoughtText.isEmpty {
                                assistant.text = thoughtText
                            }
                            assistant.modelResponseParts = modelParts.isEmpty ? nil : modelParts
                            thread = try await self.replaceLastAssistant(in: thread, with: assistant)
                            thread.updatedAt = Date()
                            thread = try await self.persist(thread)
                            continuation.yield(thread)
                            continuation.finish()
                            return
                        }
                    }
                    // Stream ended without a `done` — treat as cancelled
                    // and persist whatever we accumulated.
                    if Task.isCancelled {
                        assistant.status = .cancelled
                    } else {
                        assistant.status = .sent
                    }
                    thread = try await self.replaceLastAssistant(in: thread, with: assistant)
                    thread = try await self.persist(thread)
                    continuation.yield(thread)
                    continuation.finish()
                } catch {
                    // Mark the placeholder failed and persist so the UI
                    // can show a retry affordance.
                    var thread = conversation
                    if let last = thread.messages.last, last.role == .assistant, last.status == .streaming {
                        var failed = last
                        failed.status = .failed
                        thread.messages[thread.messages.count - 1] = failed
                    }
                    if (try? await self.persistence.upsert(thread)) != nil {
                        continuation.yield(thread)
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func persist(_ thread: ConversationThread) async throws -> ConversationThread {
        try await persistence.upsert(thread)
    }

    private func replaceLastAssistant(
        in thread: ConversationThread,
        with assistant: ChatMessage
    ) async throws -> ConversationThread {
        var updated = thread
        if let idx = updated.messages.lastIndex(where: { $0.role == .assistant }) {
            updated.messages[idx] = assistant
        }
        updated.updatedAt = Date()
        return updated
    }

    private nonisolated func buildStreamRequest(
        thread: ConversationThread,
        runtime: ConversationAIConfiguration
    ) -> RelayStreamRequest {
        let context = AIContextAssembler.assembleReplyContext(
            for: thread,
            configuration: runtime
        )
        let messages = context.recentMessages.map { message -> RelayStreamMessage in
            let modelParts = message.cleanedModelResponseParts
            let attachments: [RelayStreamAttachment]
            if modelParts == nil {
                attachments = message.attachments.map { a in
                    RelayStreamAttachment(
                        mimeType: a.mimeType,
                        base64Data: a.data.base64EncodedString(),
                        filename: a.filename
                    )
                }
            } else {
                attachments = []
            }
            return RelayStreamMessage(
                role: message.role.rawValue,
                text: modelParts == nil ? Self.requestText(for: message) : nil,
                modelResponseParts: modelParts,
                attachments: attachments
            )
        }
        return RelayStreamRequest(
            model: runtime.model,
            systemPrompt: nil,
            systemInstructionParts: context.systemInstructionParts,
            thinkingIntensity: runtime.thinkingIntensity,
            maxOutputTokens: AIModelCatalog.maxOutputTokens(for: runtime.model),
            includeThoughts: true,
            usesGoogleSearch: runtime.usesGoogleSearch,
            usesCodeExecution: runtime.usesCodeExecution,
            messages: messages
        )
    }

    private static func requestText(for message: ChatMessage) -> String? {
        if let text = message.cleanedText.nonEmptyTrimmed {
            return text
        }
        guard message.role == .user, message.attachments.contains(where: \.isAudio) else {
            return nil
        }
        return "Listen to the attached audio, infer the user's request, and answer it directly."
    }
}
