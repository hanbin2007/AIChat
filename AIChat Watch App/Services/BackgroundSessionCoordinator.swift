//
//  BackgroundSessionCoordinator.swift
//  AIChat Watch App
//
//  Wraps `WKExtendedRuntimeSession` so a streaming relay reply can
//  keep flowing for a few minutes after the wrist drops or the
//  display sleeps. The coordinator is a single-instance @MainActor
//  facade owned by `AppEnvironment`; the `ConversationDetailViewModel`
//  calls `begin()` when a turn starts and `end()` in a `defer` when
//  it completes (success, failure, or cancellation).
//
//  The session creation is factored behind `BackgroundSessionHandle`
//  so unit tests can inject a stub instead of the real WatchKit type
//  (which is unavailable in test bundles and ineffective in a
//  simulator anyway).
//

import Foundation
#if os(watchOS)
import WatchKit
#endif

protocol BackgroundSessionHandle: AnyObject {
    func start()
    func invalidate()
}

@MainActor
final class BackgroundSessionCoordinator {
    private let factory: @MainActor () -> BackgroundSessionHandle
    private var current: BackgroundSessionHandle?

    init(factory: @escaping @MainActor () -> BackgroundSessionHandle = BackgroundSessionCoordinator.defaultFactory) {
        self.factory = factory
    }

    /// Begin a background session. Idempotent: if a session is already
    /// active this is a no-op so a stream that re-enters the path
    /// doesn't double up.
    func begin() {
        guard current == nil else { return }
        let handle = factory()
        current = handle
        handle.start()
    }

    /// Invalidate the active session, if any.
    func end() {
        guard let handle = current else { return }
        current = nil
        handle.invalidate()
    }

    /// Test-visible probe.
    var isActive: Bool { current != nil }

    nonisolated private static var defaultFactory: @MainActor () -> BackgroundSessionHandle {
        {
            #if os(watchOS)
            return WKExtendedRuntimeSessionAdapter()
            #else
            return NoopBackgroundSessionHandle()
            #endif
        }
    }
}

// MARK: - Adapters

#if os(watchOS)

@MainActor
private final class WKExtendedRuntimeSessionAdapter: NSObject, BackgroundSessionHandle, WKExtendedRuntimeSessionDelegate {
    private let session: WKExtendedRuntimeSession

    override init() {
        self.session = WKExtendedRuntimeSession()
        super.init()
        session.delegate = self
    }

    func start() {
        session.start()
    }

    func invalidate() {
        session.invalidate()
    }

    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        // Nothing to do here — the coordinator already cleared its
        // reference when the caller invoked `end()`. If the system
        // invalidated us first, the next `begin()` will spin up a
        // fresh adapter.
    }
}

#else

private final class NoopBackgroundSessionHandle: BackgroundSessionHandle {
    func start() {}
    func invalidate() {}
}

#endif
