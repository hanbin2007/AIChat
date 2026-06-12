//
//  StreamingTextPacer.swift
//  AIChat Watch App
//
//  Frame-synced reveal pacer for LLM streaming. Decouples network-cadence
//  token arrival from on-screen reveal cadence so the user sees a steady,
//  natural typing rhythm instead of bursty 120ms chunks.
//
//  Why this exists:
//  - Network delivers tokens in irregular bursts + pauses.
//  - Previous flush-throttle (120ms) coalesced bursts into visible "jumps".
//  - This pacer buffers all arrivals and reveals at ~30Hz with an adaptive
//    chars/tick rate: slow stream → slow typing, fast stream → faster
//    typing, stream end → rapid drain.
//
//  Why it's scoped to its own ObservableObject (not on ChatStore):
//  - Only the streaming bubble observes it. `@Published conversations` is
//    not touched per-token, so the whole ConversationDetailView tree stays
//    quiet during streaming.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StreamingTextPacer: ObservableObject {

    nonisolated struct Configuration {
        var tickInterval: TimeInterval = 1.0 / 30.0
        /// When pending > this, use finalize-style aggressive drain even while streaming.
        var drainOverflowThreshold: Int = 400
        /// Called when the ticker revealed characters (used to coordinate UI signals like auto-scroll).
        /// The ticker is already `@MainActor`-scoped, so the callback runs on the main actor
        /// without needing an explicit attribute — which would otherwise propagate main-actor
        /// isolation into this static default and trip Swift 6 strict-concurrency warnings.
        var onReveal: (() -> Void)?

        static let `default` = Configuration()
    }

    @Published private(set) var targetMessageID: UUID?
    @Published private(set) var revealedText: String = ""
    @Published private(set) var revealedThoughtSummary: String = ""
    @Published private(set) var isActive: Bool = false

    private var configuration: Configuration
    private var answerBuffer = GraphemeRevealBuffer()
    private var thoughtBuffer = GraphemeRevealBuffer()
    private var isFinalizing: Bool = false
    private var isPaused: Bool = false
    private var tickerTask: Task<Void, Never>?
    private var finalizationContinuations: [CheckedContinuation<Void, Never>] = []

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Lifecycle

    func begin(messageID: UUID) {
        cancelTicker()
        resolveFinalizationContinuations()

        targetMessageID = messageID
        revealedText = ""
        revealedThoughtSummary = ""
        answerBuffer.reset()
        thoughtBuffer.reset()
        isFinalizing = false
        isActive = true
    }

    func appendAnswer(_ delta: String) {
        guard isActive, delta.isEmpty == false else { return }
        answerBuffer.append(delta)
        ensureTickerRunning()
    }

    /// Pause reveal ticks. Buffered deltas continue accumulating; on resume
    /// the ticker wakes and catches up via the adaptive rate. Used to stay
    /// out of the way of active scroll gestures.
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        if paused {
            cancelTicker()
        } else if isActive {
            ensureTickerRunning()
        }
    }

    func appendThoughtSummary(_ delta: String) {
        guard isActive, delta.isEmpty == false else { return }
        thoughtBuffer.append(delta)
        ensureTickerRunning()
    }

    /// Drain remaining buffer, then mark inactive. Awaitable so the caller can
    /// commit finalized message state only after pixels match the final text.
    func finalize() async {
        guard isActive else { return }
        isFinalizing = true
        isPaused = false // finalize must never stall behind a paused gesture window
        ensureTickerRunning()

        await withCheckedContinuation { continuation in
            if hasBufferPending == false {
                revealFully()
                tearDown()
                continuation.resume()
                return
            }
            finalizationContinuations.append(continuation)
        }
    }

    /// Abandon the stream mid-flight. Commits whatever's buffered immediately.
    func cancel() {
        guard isActive else { return }
        cancelTicker()
        revealFully()
        tearDown()
    }

    // MARK: - Snapshot accessors (for persistence)

    var bufferedAnswerText: String { answerBuffer.fullText }
    var bufferedThoughtText: String { thoughtBuffer.fullText }

    // MARK: - Internals

    private var hasBufferPending: Bool {
        answerBuffer.pendingCount > 0 || thoughtBuffer.pendingCount > 0
    }

    private func ensureTickerRunning() {
        guard tickerTask == nil, isPaused == false else { return }
        let interval = configuration.tickInterval
        tickerTask = Task { @MainActor [weak self] in
            let sleepNs = UInt64(max(interval, 0.001) * 1_000_000_000)
            while Task.isCancelled == false {
                guard let self else { return }
                let didReveal = self.tick()
                if didReveal {
                    self.configuration.onReveal?()
                }
                if self.hasBufferPending == false {
                    if self.isFinalizing {
                        self.tearDown()
                        self.resolveFinalizationContinuations()
                    } else {
                        self.tickerTask = nil
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    private func cancelTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func tearDown() {
        cancelTicker()
        isActive = false
        isFinalizing = false
    }

    private func resolveFinalizationContinuations() {
        let pending = finalizationContinuations
        finalizationContinuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    @discardableResult
    private func tick() -> Bool {
        var didReveal = false

        let thoughtPending = thoughtBuffer.pendingCount
        if thoughtPending > 0 {
            let chunk = adaptiveChunkSize(pending: thoughtPending)
            appendRevealed(toThought: chunk)
            didReveal = true
        }

        let textPending = answerBuffer.pendingCount
        if textPending > 0 {
            let chunk = adaptiveChunkSize(pending: textPending)
            appendRevealed(toAnswer: chunk)
            didReveal = true
        }

        return didReveal
    }

    private func revealFully() {
        if answerBuffer.pendingCount > 0 {
            appendRevealed(toAnswer: answerBuffer.pendingCount)
        }
        if thoughtBuffer.pendingCount > 0 {
            appendRevealed(toThought: thoughtBuffer.pendingCount)
        }
    }

    private func appendRevealed(toAnswer count: Int) {
        revealedText.append(contentsOf: answerBuffer.reveal(maxCount: count))
    }

    private func appendRevealed(toThought count: Int) {
        revealedThoughtSummary.append(contentsOf: thoughtBuffer.reveal(maxCount: count))
    }

    private func adaptiveChunkSize(pending: Int) -> Int {
        if isFinalizing || pending >= configuration.drainOverflowThreshold {
            return min(pending, 64)
        }
        if pending <= 10 { return 1 }
        if pending <= 40 { return 2 }
        if pending <= 120 { return 4 }
        if pending <= 300 { return 8 }
        return min(pending, 16)
    }

    #if DEBUG
    func revealSynchronouslyForTesting(maxChunkSize: Int) {
        let chunkSize = max(maxChunkSize, 1)
        while hasBufferPending {
            let thoughtChunk = min(thoughtBuffer.pendingCount, chunkSize)
            if thoughtChunk > 0 {
                appendRevealed(toThought: thoughtChunk)
            }

            let answerChunk = min(answerBuffer.pendingCount, chunkSize)
            if answerChunk > 0 {
                appendRevealed(toAnswer: answerChunk)
            }
        }
    }
    #endif
}

private struct GraphemeRevealBuffer {
    private(set) var fullText: String = ""

    private var chunks: [String] = []
    private var headChunkOffset: Int = 0
    private var headIndex: String.Index?
    private var totalCount: Int = 0
    private var revealedCount: Int = 0

    var pendingCount: Int {
        totalCount - revealedCount
    }

    mutating func reset() {
        fullText = ""
        chunks.removeAll(keepingCapacity: true)
        headChunkOffset = 0
        headIndex = nil
        totalCount = 0
        revealedCount = 0
    }

    mutating func append(_ delta: String) {
        guard delta.isEmpty == false else { return }

        fullText.append(delta)
        chunks.append(delta)
        totalCount += delta.count
    }

    mutating func reveal(maxCount: Int) -> String {
        guard maxCount > 0, pendingCount > 0 else { return "" }

        var remaining = min(maxCount, pendingCount)
        var revealed = String()
        revealed.reserveCapacity(remaining)

        while remaining > 0, headChunkOffset < chunks.count {
            let chunk = chunks[headChunkOffset]
            let start = headIndex ?? chunk.startIndex

            if start == chunk.endIndex {
                advanceHeadChunk()
                continue
            }

            let end = chunk.index(start, offsetBy: remaining, limitedBy: chunk.endIndex) ?? chunk.endIndex
            let slice = chunk[start..<end]
            let count = slice.count

            revealed.append(contentsOf: slice)
            revealedCount += count
            remaining -= count

            if end == chunk.endIndex {
                advanceHeadChunk()
            } else {
                headIndex = end
            }
        }

        return revealed
    }

    private mutating func advanceHeadChunk() {
        headChunkOffset += 1
        headIndex = nil

        if headChunkOffset >= 32 {
            chunks.removeFirst(headChunkOffset)
            headChunkOffset = 0
        }
    }
}
