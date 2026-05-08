//
//  ConversationDetailViewModel.swift
//  AIChat Watch App
//
//  Drives the per-conversation detail screen — composing a message,
//  streaming the assistant reply, voice transcription, error/retry
//  surfacing, and low-balance CTA.
//
//  Bound 1:1 to a single conversation id; constructed by the parent
//  list view when the user navigates in. Holds its own `ConversationThread`
//  snapshot rather than reaching back into a list-level cache, so each
//  detail screen is self-contained.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConversationDetailViewModel {
    enum SendState: Equatable {
        case idle
        case sending
        case streaming
        case failed(String)
    }

    enum TranscribeState: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var conversation: ConversationThread
    private(set) var sendState: SendState = .idle
    private(set) var transcribeState: TranscribeState = .idle
    private(set) var lowBalanceVisible: Bool = false

    private let chatService: any ChatServiceProtocol
    private let transcriptionService: TranscriptionService
    private let persistence: ConversationPersistence
    private let connection: RelayConnectionMonitor
    /// Marked nonisolated(unsafe) so `deinit` (which is itself
    /// nonisolated in Swift 6) can cancel the in-flight stream.
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?

    init(
        conversation: ConversationThread,
        chatService: any ChatServiceProtocol,
        transcriptionService: TranscriptionService,
        persistence: ConversationPersistence,
        connection: RelayConnectionMonitor
    ) {
        self.conversation = conversation
        self.chatService = chatService
        self.transcriptionService = transcriptionService
        self.persistence = persistence
        self.connection = connection
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Send

    func send(text: String, attachments: [ChatAttachment]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        cancelStream()
        sendState = .sending
        lowBalanceVisible = false

        let snapshot = conversation
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = await self.chatService.send(
                    userText: trimmed,
                    attachments: attachments,
                    to: snapshot
                )
                self.sendState = .streaming
                for try await update in stream {
                    if Task.isCancelled { break }
                    self.conversation = update
                }
                self.sendState = .idle
            } catch let error as RelayClientError {
                self.handle(relayError: error)
            } catch {
                self.sendState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if sendState == .streaming || sendState == .sending {
            sendState = .idle
        }
    }

    func retryLast() {
        // Drop the last failed assistant message + its preceding user
        // message text/attachments, then re-send.
        guard let lastAssistantIndex = conversation.messages.lastIndex(where: { $0.role == .assistant }) else { return }
        let assistant = conversation.messages[lastAssistantIndex]
        guard assistant.status == .failed else { return }
        let userIndex = lastAssistantIndex - 1
        guard userIndex >= 0,
              conversation.messages[userIndex].role == .user else { return }
        let user = conversation.messages[userIndex]
        var trimmed = conversation
        trimmed.messages.removeLast(2)
        self.conversation = trimmed
        Task { try? await persistence.upsert(trimmed) }
        send(text: user.text, attachments: user.attachments)
    }

    // MARK: - Transcribe

    func transcribe(_ audio: ChatAttachment, model: String, customPrompt: String, includesContext: Bool, existingDraft: String) async -> String? {
        transcribeState = .transcribing
        let configuration = VoiceTranscriptionConfiguration(
            model: model,
            customPrompt: customPrompt,
            includesContext: includesContext,
            existingDraftText: existingDraft
        )
        do {
            let result = try await transcriptionService.transcribe(audio, in: conversation, configuration: configuration)
            transcribeState = .idle
            return result.text
        } catch {
            transcribeState = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Configuration / persistence helpers

    func updateTitle(_ title: String) {
        var thread = conversation
        thread.title = title
        thread.updatedAt = Date()
        self.conversation = thread
        Task { try? await persistence.upsert(thread) }
    }

    func updateAIConfiguration(_ configuration: ConversationAIConfiguration) {
        var thread = conversation
        thread.aiConfiguration = configuration
        thread.updatedAt = Date()
        self.conversation = thread
        Task { try? await persistence.upsert(thread) }
    }

    // MARK: - Errors

    private func handle(relayError: RelayClientError) {
        switch relayError {
        case .paymentRequired(let message):
            lowBalanceVisible = true
            sendState = .failed(message ?? relayError.localizedDescription)
        default:
            sendState = .failed(relayError.localizedDescription)
        }
    }
}
