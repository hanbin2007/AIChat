//
//  RetryingChatServiceTests.swift
//  AIChat Watch AppTests
//
//  Pins the §2.2 contract:
//    - Retries pre-yield failures up to maxAttempts with exponential
//      backoff against an injected fake sleeper.
//    - Stops retrying once the inner stream has yielded any snapshot
//      (i.e. once user message + assistant placeholder have been
//      persisted) — that point is the boundary between "transient
//      connection failure" and "user-visible failure".
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class RetryingChatServiceTests: XCTestCase {

    func test_passesThroughOnFirstAttemptSuccess() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [.yieldThenFinish([snapshot])])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 3, initialDelayNanos: 1_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        let collected = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(stub.attemptCount, 1)
        XCTAssertEqual(sleeper.delays, [])
    }

    func test_retriesOnPreYieldFailure_thenSucceeds() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [
            .immediateFail(StubError.boom),
            .immediateFail(StubError.boom),
            .yieldThenFinish([snapshot])
        ])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 3, initialDelayNanos: 1_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        let collected = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(stub.attemptCount, 3)
    }

    func test_doesNotRetryAfterFirstYield() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [
            .yieldThenFail([snapshot], StubError.boom)
        ])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 5, initialDelayNanos: 1_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        var caught: Error?
        var collected: [ConversationThread] = []
        do {
            collected = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))
        } catch {
            caught = error
        }

        XCTAssertNotNil(caught)
        XCTAssertEqual(collected.count, 1, "should preserve the snapshot that was yielded before the failure")
        XCTAssertEqual(stub.attemptCount, 1, "must not retry once a snapshot has been yielded")
        XCTAssertEqual(sleeper.delays, [])
    }

    func test_throwsAfterExhaustingAttempts() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [
            .immediateFail(StubError.boom),
            .immediateFail(StubError.boom),
            .immediateFail(StubError.boom)
        ])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 3, initialDelayNanos: 1_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        var caught: Error?
        do {
            _ = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))
        } catch {
            caught = error
        }

        XCTAssertNotNil(caught)
        XCTAssertEqual(stub.attemptCount, 3)
    }

    func test_respectsExponentialBackoff() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [
            .immediateFail(StubError.boom),
            .immediateFail(StubError.boom),
            .yieldThenFinish([snapshot])
        ])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 5, initialDelayNanos: 2_000_000_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        _ = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))

        // After attempt 1 fails: sleep 2e9. After attempt 2 fails: sleep 4e9.
        // Attempt 3 succeeds → no further sleep.
        XCTAssertEqual(sleeper.delays, [2_000_000_000, 4_000_000_000])
    }

    func test_maxAttemptsBelowOneIsClampedToOne() async throws {
        let snapshot = ConversationThread(title: "T")
        let stub = StubChatService(script: [.immediateFail(StubError.boom)])
        let sleeper = RecordingSleeper()
        let service = RetryingChatService(
            inner: stub,
            policyProvider: { .init(maxAttempts: 0, initialDelayNanos: 1_000, factor: 2.0) },
            sleeper: sleeper.callable
        )

        var caught: Error?
        do {
            _ = try await collect(service.send(userText: "hi", attachments: [], to: snapshot))
        } catch {
            caught = error
        }

        XCTAssertNotNil(caught)
        XCTAssertEqual(stub.attemptCount, 1)
    }

    // MARK: - Helpers

    private func collect(
        _ stream: AsyncThrowingStream<ConversationThread, Error>
    ) async throws -> [ConversationThread] {
        var out: [ConversationThread] = []
        for try await s in stream { out.append(s) }
        return out
    }
}

// MARK: - Stubs

enum StubChatServiceOutcome: Sendable {
    case yieldThenFinish([ConversationThread])
    case yieldThenFail([ConversationThread], Error)
    case immediateFail(Error)
}

final class StubChatService: ChatServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _script: [StubChatServiceOutcome]
    private var attempts: Int = 0

    init(script: [StubChatServiceOutcome]) {
        self._script = script
    }

    var script: [StubChatServiceOutcome] {
        get {
            lock.lock(); defer { lock.unlock() }
            return _script
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _script = newValue
            attempts = 0
        }
    }

    var attemptCount: Int {
        lock.lock(); defer { lock.unlock() }
        return attempts
    }

    nonisolated func send(
        userText: String,
        attachments: [ChatAttachment],
        to conversation: ConversationThread
    ) -> AsyncThrowingStream<ConversationThread, Error> {
        let outcome: StubChatServiceOutcome = {
            lock.lock(); defer { lock.unlock() }
            let idx = attempts
            attempts += 1
            return idx < _script.count ? _script[idx] : .immediateFail(StubError.scriptExhausted)
        }()
        return AsyncThrowingStream { continuation in
            switch outcome {
            case .yieldThenFinish(let snaps):
                for s in snaps { continuation.yield(s) }
                continuation.finish()
            case .yieldThenFail(let snaps, let err):
                for s in snaps { continuation.yield(s) }
                continuation.finish(throwing: err)
            case .immediateFail(let err):
                continuation.finish(throwing: err)
            }
        }
    }
}

enum StubError: Error, Equatable {
    case boom
    case scriptExhausted
}

final class RecordingSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var _delays: [UInt64] = []

    var delays: [UInt64] {
        lock.lock(); defer { lock.unlock() }
        return _delays
    }

    var callable: @Sendable (UInt64) async -> Void {
        { [weak self] nanos in
            self?.record(nanos)
        }
    }

    private func record(_ nanos: UInt64) {
        lock.lock(); defer { lock.unlock() }
        _delays.append(nanos)
    }
}
