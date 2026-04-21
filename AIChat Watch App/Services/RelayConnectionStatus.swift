//
//  RelayConnectionStatus.swift
//  AIChat Watch App
//
//  Tracks the relay backend's health so the toolbar dot can reflect it
//  without waiting for a user-visible send failure. Relay-mode only —
//  never observed by direct-mode code paths.
//

import Foundation
import os

/// Visible states for the relay connection indicator.
///
/// Legal transitions (state machine):
/// - `unknown` → `connecting`
/// - `connecting` → `online | offline(reason:)`
/// - `online` → `connecting` (new request starts)
/// - `offline(reason:)` → `connecting` (retry triggered)
///
/// `unknown` is the cold-start state — the indicator must not lie and
/// claim `online` before the first round-trip completes.
nonisolated enum RelayConnectionStatus: Equatable {
    case unknown
    case connecting
    case online
    case offline(reason: String)

    static func == (lhs: RelayConnectionStatus, rhs: RelayConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown), (.connecting, .connecting), (.online, .online):
            return true
        case let (.offline(a), .offline(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Bridge between the nonisolated `RelayAIClient` struct (whose callbacks
/// run on URLSession's background queue) and the `@MainActor`-isolated
/// `ChatStore` that owns the published status.
///
/// Owned as a reference type so struct copies of `RelayAIClient` share
/// the same sink. All mutations flip to the main actor before touching
/// `onChange`. A 250ms debounce collapses rapid-flap transitions so the
/// UI dot does not flicker when many concurrent requests fail in a
/// burst.
final class RelayConnectionStatusHandler: @unchecked Sendable {
    /// Debounce window. Status transitions that arrive more frequently
    /// than this are coalesced to the most recent value.
    static let debounceInterval: TimeInterval = 0.25

    private let log = Logger(subsystem: "com.aichat.watch", category: "RelayConnectionStatus")
    private let lock = NSLock()

    private var _onChange: (@MainActor (RelayConnectionStatus) -> Void)?
    private var _lastEmittedStatus: RelayConnectionStatus = .unknown
    private var _lastEmittedAt: Date?
    private var _pendingDeliveryTask: Task<Void, Never>?
    private var _pendingStatus: RelayConnectionStatus?
    private let debounceInterval: TimeInterval
    private let now: @Sendable () -> Date

    init(
        debounceInterval: TimeInterval = RelayConnectionStatusHandler.debounceInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.debounceInterval = debounceInterval
        self.now = now
    }

    /// Assigns the sink that receives coalesced status transitions.
    @MainActor
    func setOnChange(_ handler: @escaping @MainActor (RelayConnectionStatus) -> Void) {
        lock.lock()
        _onChange = handler
        lock.unlock()
    }

    /// Reports a new status. Safe to call from any actor / any queue.
    /// Duplicate consecutive statuses are dropped. Rapid bursts are
    /// debounced — at most one delivery per `debounceInterval`.
    nonisolated func report(_ status: RelayConnectionStatus) {
        lock.lock()

        if status == _lastEmittedStatus && _pendingStatus == nil {
            lock.unlock()
            return
        }

        let nowDate = now()
        let lastAt = _lastEmittedAt
        let interval = debounceInterval
        let elapsed = lastAt.map { nowDate.timeIntervalSince($0) } ?? .infinity

        if elapsed >= interval {
            _lastEmittedStatus = status
            _lastEmittedAt = nowDate
            _pendingStatus = nil
            _pendingDeliveryTask?.cancel()
            _pendingDeliveryTask = nil
            let handlerSnapshot = _onChange
            lock.unlock()

            logTransition(status)
            Task { @MainActor in
                handlerSnapshot?(status)
            }
            return
        }

        // Within debounce window — schedule a delayed delivery of the
        // latest status and cancel any earlier pending one.
        _pendingStatus = status
        _pendingDeliveryTask?.cancel()
        let delayNanoseconds = UInt64(max(0, interval - elapsed) * 1_000_000_000)
        _pendingDeliveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            self?.flushPending()
        }
        lock.unlock()
    }

    private func flushPending() {
        lock.lock()
        guard let pending = _pendingStatus else {
            lock.unlock()
            return
        }
        let shouldEmit = pending != _lastEmittedStatus
        _pendingStatus = nil
        _pendingDeliveryTask = nil
        if shouldEmit {
            _lastEmittedStatus = pending
            _lastEmittedAt = now()
        }
        let handlerSnapshot = _onChange
        lock.unlock()

        guard shouldEmit else {
            return
        }

        logTransition(pending)
        Task { @MainActor in
            handlerSnapshot?(pending)
        }
    }

    private func logTransition(_ status: RelayConnectionStatus) {
        switch status {
        case .unknown:
            break
        case .connecting:
            log.debug("Relay connecting")
        case .online:
            log.debug("Relay online")
        case .offline(let reason):
            // Log offline reason at INFO (reason, not token). Keep it
            // to one line per transition; do not log on every request.
            log.info("Relay offline: \(reason, privacy: .public)")
        }
    }
}
