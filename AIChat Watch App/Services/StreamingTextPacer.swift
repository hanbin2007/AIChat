//
//  StreamingTextPacer.swift
//  AIChat Watch App
//
//  Decouples the relay's SSE delta cadence (which can dump dozens of
//  characters in a single yield) from the on-screen reveal cadence
//  (~30 Hz, character-level). The pacer wraps an upstream
//  `AsyncThrowingStream<ConversationThread, Error>` from `ChatService`
//  and emits a downstream stream of the same shape, where the last
//  assistant message's `text` and `thoughtSummary` are truncated to
//  the number of characters revealed so far. `modelResponseParts`,
//  attachments, and message status are passed through unchanged on
//  the final yield only — structured tool/code-block content should
//  appear in one piece, not character-by-character.
//
//  Cancellation flows both ways: if the downstream consumer
//  terminates, the upstream task and tick loop are cancelled; if
//  the upstream throws, the pacer propagates the error without
//  revealing any further characters (otherwise we'd be inflating
//  text on a `.failed` placeholder).
//

import Foundation

final class StreamingTextPacer: Sendable {

    struct Configuration: Sendable {
        let tickInterval: Duration
        let baseCharsPerTick: Int
        let maxCharsPerTick: Int
        let backlogScale: Double

        static let `default` = Configuration(
            tickInterval: .milliseconds(33),
            baseCharsPerTick: 4,
            maxCharsPerTick: 24,
            backlogScale: 0.25
        )
    }

    let configuration: Configuration
    private let sleeper: @Sendable (Duration) async throws -> Void

    init(
        configuration: Configuration = .default,
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.configuration = configuration
        self.sleeper = sleeper
    }

    func pace(
        _ upstream: AsyncThrowingStream<ConversationThread, Error>
    ) -> AsyncThrowingStream<ConversationThread, Error> {
        let configuration = self.configuration
        let sleeper = self.sleeper
        return AsyncThrowingStream { continuation in
            let session = PacerSession(
                configuration: configuration,
                sleeper: sleeper,
                continuation: continuation,
                upstream: upstream
            )
            session.start()
            continuation.onTermination = { _ in session.cancel() }
        }
    }
}

// MARK: - Per-call session

private final class PacerSession: @unchecked Sendable {

    private enum TickDecision {
        case skip
        case yield(ConversationThread)
        case finalYield(ConversationThread)
        case finishOnly
        case fail(Error)
    }

    private let configuration: StreamingTextPacer.Configuration
    private let sleeper: @Sendable (Duration) async throws -> Void
    private let continuation: AsyncThrowingStream<ConversationThread, Error>.Continuation
    private let upstream: AsyncThrowingStream<ConversationThread, Error>

    private let lock = NSLock()
    private var latest: ConversationThread?
    private var revealedTextLength: Int = 0
    private var revealedThoughtLength: Int = 0
    private var lastAssistantID: UUID?
    private var upstreamFinished: Bool = false
    private var upstreamError: Error?
    private var didFinish: Bool = false

    private var consumerTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(
        configuration: StreamingTextPacer.Configuration,
        sleeper: @escaping @Sendable (Duration) async throws -> Void,
        continuation: AsyncThrowingStream<ConversationThread, Error>.Continuation,
        upstream: AsyncThrowingStream<ConversationThread, Error>
    ) {
        self.configuration = configuration
        self.sleeper = sleeper
        self.continuation = continuation
        self.upstream = upstream
    }

    func start() {
        consumerTask = Task { [weak self] in await self?.consumeUpstream() }
        tickTask = Task { [weak self] in await self?.runTickLoop() }
    }

    func cancel() {
        consumerTask?.cancel()
        tickTask?.cancel()
    }

    // MARK: - Upstream

    private func consumeUpstream() async {
        do {
            for try await snapshot in upstream {
                if Task.isCancelled { break }
                lock.lock()
                latest = snapshot
                lock.unlock()
            }
            lock.lock()
            upstreamFinished = true
            lock.unlock()
        } catch {
            lock.lock()
            upstreamError = error
            upstreamFinished = true
            lock.unlock()
        }
    }

    // MARK: - Tick loop

    private func runTickLoop() async {
        while true {
            if Task.isCancelled { return }
            do {
                try await sleeper(configuration.tickInterval)
            } catch {
                return
            }
            let decision = computeTickDecision()
            apply(decision)
            if shouldStop(after: decision) { return }
        }
    }

    private func shouldStop(after decision: TickDecision) -> Bool {
        switch decision {
        case .finalYield, .finishOnly, .fail:
            return true
        case .skip, .yield:
            return false
        }
    }

    // MARK: - Decision

    private func computeTickDecision() -> TickDecision {
        lock.lock(); defer { lock.unlock() }

        if didFinish { return .skip }

        if let error = upstreamError {
            didFinish = true
            return .fail(error)
        }

        guard let latest else {
            if upstreamFinished {
                didFinish = true
                return .finishOnly
            }
            return .skip
        }

        guard let assistantIdx = latest.messages.lastIndex(where: { $0.role == .assistant }) else {
            // ChatService always appends a streaming-placeholder
            // assistant message before its first yield, so this branch
            // is unreachable in production. If we ever see it, just
            // wait — finishing the stream is more correct than
            // yielding a snapshot the caller hasn't been told about
            // yet via the regular path.
            if upstreamFinished {
                didFinish = true
                return .finishOnly
            }
            return .skip
        }

        let assistant = latest.messages[assistantIdx]
        if lastAssistantID != assistant.id {
            lastAssistantID = assistant.id
            revealedTextLength = 0
            revealedThoughtLength = 0
        }

        let textTotal = assistant.text.count
        let thoughtTotal = assistant.thoughtSummary?.count ?? 0
        let textBacklog = max(0, textTotal - revealedTextLength)
        let thoughtBacklog = max(0, thoughtTotal - revealedThoughtLength)

        revealedTextLength = min(textTotal, revealedTextLength + advance(forBacklog: textBacklog))
        revealedThoughtLength = min(thoughtTotal, revealedThoughtLength + advance(forBacklog: thoughtBacklog))

        let fullyDrained = revealedTextLength >= textTotal && revealedThoughtLength >= thoughtTotal
        if upstreamFinished, fullyDrained {
            didFinish = true
            return .finalYield(latest)
        }

        var truncated = assistant
        truncated.text = String(assistant.text.prefix(revealedTextLength))
        if let thought = assistant.thoughtSummary {
            truncated.thoughtSummary = String(thought.prefix(revealedThoughtLength))
        }
        // Hide structured model parts (code blocks, tool results)
        // until the final yield — these should appear in one piece,
        // not character-by-character.
        truncated.modelResponseParts = nil

        var modified = latest
        modified.messages[assistantIdx] = truncated
        return .yield(modified)
    }

    private func advance(forBacklog backlog: Int) -> Int {
        guard backlog > 0 else { return 0 }
        let scaled = configuration.baseCharsPerTick + Int(Double(backlog) * configuration.backlogScale)
        let bounded = min(configuration.maxCharsPerTick, max(configuration.baseCharsPerTick, scaled))
        return min(backlog, bounded)
    }

    // MARK: - Apply

    private func apply(_ decision: TickDecision) {
        switch decision {
        case .skip:
            return
        case .yield(let thread):
            continuation.yield(thread)
        case .finalYield(let thread):
            continuation.yield(thread)
            continuation.finish()
        case .finishOnly:
            continuation.finish()
        case .fail(let error):
            continuation.finish(throwing: error)
        }
    }
}
