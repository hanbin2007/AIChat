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

    struct Configuration {
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
    private var bufferedText: String = ""
    private var bufferedThoughtSummary: String = ""
    private var bufferedTextCount: Int = 0
    private var bufferedThoughtCount: Int = 0
    private var revealedTextCount: Int = 0
    private var revealedThoughtCount: Int = 0
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
        bufferedText = ""
        bufferedThoughtSummary = ""
        bufferedTextCount = 0
        bufferedThoughtCount = 0
        revealedTextCount = 0
        revealedThoughtCount = 0
        isFinalizing = false
        isActive = true
    }

    func appendAnswer(_ delta: String) {
        guard isActive, delta.isEmpty == false else { return }
        bufferedText.append(delta)
        bufferedTextCount += delta.count
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
        bufferedThoughtSummary.append(delta)
        bufferedThoughtCount += delta.count
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

    var bufferedAnswerText: String { bufferedText }
    var bufferedThoughtText: String { bufferedThoughtSummary }

    // MARK: - Internals

    private var hasBufferPending: Bool {
        bufferedTextCount > revealedTextCount || bufferedThoughtCount > revealedThoughtCount
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

        let thoughtPending = bufferedThoughtCount - revealedThoughtCount
        if thoughtPending > 0 {
            let chunk = adaptiveChunkSize(pending: thoughtPending)
            appendRevealed(toThought: chunk)
            didReveal = true
        }

        let textPending = bufferedTextCount - revealedTextCount
        if textPending > 0 {
            let chunk = adaptiveChunkSize(pending: textPending)
            appendRevealed(toAnswer: chunk)
            didReveal = true
        }

        return didReveal
    }

    private func revealFully() {
        if bufferedTextCount > revealedTextCount {
            appendRevealed(toAnswer: bufferedTextCount - revealedTextCount)
        }
        if bufferedThoughtCount > revealedThoughtCount {
            appendRevealed(toThought: bufferedThoughtCount - revealedThoughtCount)
        }
    }

    private func appendRevealed(toAnswer count: Int) {
        let slice = graphemeSlice(from: bufferedText, skip: revealedTextCount, take: count)
        revealedText.append(contentsOf: slice)
        revealedTextCount += count
    }

    private func appendRevealed(toThought count: Int) {
        let slice = graphemeSlice(from: bufferedThoughtSummary, skip: revealedThoughtCount, take: count)
        revealedThoughtSummary.append(contentsOf: slice)
        revealedThoughtCount += count
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

    private func graphemeSlice(from source: String, skip: Int, take: Int) -> Substring {
        guard take > 0, skip >= 0 else { return "" }
        guard let start = source.index(source.startIndex, offsetBy: skip, limitedBy: source.endIndex) else {
            return ""
        }
        guard let end = source.index(start, offsetBy: take, limitedBy: source.endIndex) else {
            return source[start..<source.endIndex]
        }
        return source[start..<end]
    }
}
