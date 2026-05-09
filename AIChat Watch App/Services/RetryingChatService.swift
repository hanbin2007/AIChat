//
//  RetryingChatService.swift
//  AIChat Watch App
//
//  Wraps a `ChatServiceProtocol` and retries connection-level failures
//  with exponential backoff. Only failures that happen *before* the
//  inner stream has yielded any snapshot are retried — once the inner
//  has emitted at least one snapshot, the user message + assistant
//  placeholder have been persisted, the UI is showing them, and a
//  silent retry would race with VM state. From that point on, errors
//  propagate to the VM, which surfaces a `.failed` state and lets the
//  user retry manually.
//

import Foundation

actor RetryingChatService: ChatServiceProtocol {

    struct RetryPolicy: Sendable {
        let maxAttempts: Int          // total attempts including the first; clamps to >= 1
        let initialDelayNanos: UInt64
        let factor: Double

        static let `default` = RetryPolicy(
            maxAttempts: 3,
            initialDelayNanos: 2_000_000_000, // 2s
            factor: 2.0                       // → 2s, 4s, 8s, ...
        )
    }

    private let inner: any ChatServiceProtocol
    private let policyProvider: @Sendable () async -> RetryPolicy
    private let sleeper: @Sendable (UInt64) async -> Void

    init(
        inner: any ChatServiceProtocol,
        policyProvider: @escaping @Sendable () async -> RetryPolicy = { .default },
        sleeper: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.inner = inner
        self.policyProvider = policyProvider
        self.sleeper = sleeper
    }

    nonisolated func send(
        userText: String,
        attachments: [ChatAttachment],
        to conversation: ConversationThread
    ) -> AsyncThrowingStream<ConversationThread, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [policyProvider, sleeper, inner] in
                let policy = await policyProvider()
                let totalAttempts = max(1, policy.maxAttempts)
                var attempt = 0
                while true {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    attempt += 1
                    var yieldedAny = false
                    do {
                        let upstream = inner.send(
                            userText: userText,
                            attachments: attachments,
                            to: conversation
                        )
                        for try await snapshot in upstream {
                            yieldedAny = true
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                        return
                    } catch {
                        if yieldedAny || attempt >= totalAttempts || Task.isCancelled {
                            continuation.finish(throwing: error)
                            return
                        }
                        let delay = UInt64(
                            Double(policy.initialDelayNanos) * pow(policy.factor, Double(attempt - 1))
                        )
                        await sleeper(delay)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
