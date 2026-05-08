//
//  StreamingTextPacerTests.swift
//  AIChat Watch AppTests
//
//  Pins the §1.1 character-level reveal contract.
//
//  Strategy: drive the pacer's tick cadence with an injected
//  controllable sleeper. Each `advanceTick()` call lets exactly one
//  tick run to completion. We push upstream snapshots, advance ticks,
//  and assert against the downstream history.
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class StreamingTextPacerTests: XCTestCase {

    func test_holdsBackTextUntilFirstTick() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()

        let pacedTask = harness.collect(pacing: upstream.stream)

        // Push a snapshot with 100 characters of assistant text.
        upstream.yieldAssistant(text: String(repeating: "x", count: 100))

        // Without ticks, no downstream yield should happen.
        try await Task.sleep(nanoseconds: 50_000_000)
        let beforeAnyTick = await harness.snapshotsSoFar()
        XCTAssertEqual(beforeAnyTick.count, 0)

        await harness.advanceTick()
        let afterOne = await harness.snapshotsSoFar()
        XCTAssertEqual(afterOne.count, 1)
        // First tick: base + scaled by backlog (100 * 0.25 = 25 → cap at maxCharsPerTick = 24)
        let firstAssistantText = afterOne[0].messages.last(where: { $0.role == .assistant })?.text ?? ""
        XCTAssertGreaterThan(firstAssistantText.count, 0)
        XCTAssertLessThan(firstAssistantText.count, 100)

        upstream.finish()
        await harness.runUntilFinish()
        pacedTask.cancel()
    }

    func test_drainsRemainingCharsAfterStreamCompletes() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        upstream.yieldAssistant(text: "Hello, world!")
        upstream.finishAssistant(text: "Hello, world!", status: .sent)
        upstream.finish()

        await harness.runUntilFinish()

        let snapshots = await harness.snapshotsSoFar()
        XCTAssertFalse(snapshots.isEmpty)
        let final = snapshots.last
        XCTAssertEqual(final?.messages.last?.text, "Hello, world!")
        XCTAssertEqual(final?.messages.last?.status, .sent)

        pacedTask.cancel()
    }

    func test_emitsFinalSnapshotWithModelPartsOnDone() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        let parts = [GeminiPartPayload(text: "Hi")]
        upstream.finishAssistant(text: "Hi", status: .sent, modelResponseParts: parts)
        upstream.finish()

        await harness.runUntilFinish()

        let final = await harness.snapshotsSoFar().last
        XCTAssertEqual(final?.messages.last?.modelResponseParts?.count, 1)

        pacedTask.cancel()
    }

    func test_intermediateSnapshotsHideModelResponseParts() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        let parts = [GeminiPartPayload(text: "secret")]
        upstream.yieldAssistant(text: String(repeating: "a", count: 200), modelResponseParts: parts)

        await harness.advanceTick()
        let mid = await harness.snapshotsSoFar().first
        XCTAssertNil(mid?.messages.last?.modelResponseParts)

        upstream.finish()
        await harness.runUntilFinish()
        pacedTask.cancel()
    }

    func test_resetsRevealCountWhenAssistantMessageIDChanges() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        upstream.yieldAssistant(text: "first turn long text body.")
        await harness.advanceTick()

        // Replace assistant entirely (new id) — tick should restart from 0.
        upstream.replaceWithFreshAssistant(text: "second turn body.")
        await harness.advanceTick()

        let snapshots = await harness.snapshotsSoFar()
        let lastText = snapshots.last?.messages.last?.text ?? ""
        // We should see characters from the second turn, not a continuation that overshoots its length.
        XCTAssertLessThanOrEqual(lastText.count, "second turn body.".count)

        upstream.finishAssistant(text: "second turn body.", status: .sent)
        upstream.finish()
        await harness.runUntilFinish()
        pacedTask.cancel()
    }

    func test_propagatesUpstreamErrorWithoutRevealingPartial() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        upstream.fail(StubError.boom)
        await harness.runUntilFinish()

        let outcome = await harness.outcome()
        guard case .failed(let error) = outcome else {
            return XCTFail("expected failure, got \(outcome)")
        }
        XCTAssertTrue((error as? StubError) == .boom)

        pacedTask.cancel()
    }

    func test_handlesMultiByteCharactersWithoutSlicingMidGrapheme() async throws {
        let harness = PacerHarness(configuration: .init(
            tickInterval: .milliseconds(33),
            baseCharsPerTick: 1,
            maxCharsPerTick: 1,
            backlogScale: 0
        ))
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        // Each user-perceived character is one Character; emoji like 🇨🇳 is one grapheme cluster.
        upstream.yieldAssistant(text: "你🇨🇳好")
        await harness.advanceTick()
        await harness.advanceTick()
        await harness.advanceTick()

        let snapshots = await harness.snapshotsSoFar()
        // Each emitted text must be a valid Character-prefix of the
        // full source — no slicing the middle of a grapheme cluster.
        for snap in snapshots {
            let text = snap.messages.last?.text ?? ""
            XCTAssertTrue("你🇨🇳好".hasPrefix(text), "text '\(text)' is not a valid prefix")
        }

        upstream.finishAssistant(text: "你🇨🇳好", status: .sent)
        upstream.finish()
        await harness.runUntilFinish()
        pacedTask.cancel()
    }

    func test_downstreamCancellationStopsTicking() async throws {
        let harness = PacerHarness()
        let upstream = PacerUpstream()
        let pacedTask = harness.collect(pacing: upstream.stream)

        upstream.yieldAssistant(text: "long body of text to reveal")
        await harness.advanceTick()
        pacedTask.cancel()

        // After cancel, sleeper should stop being called.
        try await Task.sleep(nanoseconds: 50_000_000)
        let pending = await harness.pendingSleepers()
        XCTAssertEqual(pending, 0)
    }
}

// MARK: - Harness

@MainActor
private final class PacerHarness {

    enum Outcome {
        case running
        case finished
        case failed(Error)
    }

    private let pacer: StreamingTextPacer
    private let sleeper: ManualSleeper
    private var snapshots: [ConversationThread] = []
    private var outcomeValue: Outcome = .running

    init(configuration: StreamingTextPacer.Configuration = .default) {
        let sleeper = ManualSleeper()
        self.sleeper = sleeper
        self.pacer = StreamingTextPacer(configuration: configuration, sleeper: sleeper.callable)
    }

    func collect(pacing upstream: AsyncThrowingStream<ConversationThread, Error>) -> Task<Void, Never> {
        let stream = pacer.pace(upstream)
        return Task { [weak self] in
            do {
                for try await snap in stream {
                    await self?.appendSnapshot(snap)
                }
                await self?.markFinished()
            } catch {
                await self?.markFailed(error)
            }
        }
    }

    private func appendSnapshot(_ s: ConversationThread) {
        snapshots.append(s)
    }

    private func markFinished() { outcomeValue = .finished }
    private func markFailed(_ e: Error) { outcomeValue = .failed(e) }

    func snapshotsSoFar() -> [ConversationThread] { snapshots }

    func outcome() -> Outcome { outcomeValue }

    func advanceTick() async {
        await sleeper.releaseOne()
        // Give the tick task a chance to compute and yield.
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    func runUntilFinish(timeout: Duration = .seconds(2)) async {
        let start = Date()
        while case .running = outcomeValue {
            await sleeper.releaseAll()
            try? await Task.sleep(nanoseconds: 10_000_000)
            if Date().timeIntervalSince(start) > 2.0 { break }
        }
    }

    func pendingSleepers() async -> Int {
        await sleeper.pendingCount()
    }
}

private actor ManualSleeper {
    private var continuations: [CheckedContinuation<Void, Error>] = []

    nonisolated var callable: @Sendable (Duration) async throws -> Void {
        { [weak self] _ in
            guard let self else { return }
            try await self.suspend()
        }
    }

    private func suspend() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuations.append(cont)
        }
    }

    func releaseOne() {
        guard !continuations.isEmpty else { return }
        let cont = continuations.removeFirst()
        cont.resume()
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for c in pending { c.resume() }
    }

    func pendingCount() -> Int { continuations.count }
}

// MARK: - Upstream

@MainActor
private final class PacerUpstream {
    let stream: AsyncThrowingStream<ConversationThread, Error>
    private let continuation: AsyncThrowingStream<ConversationThread, Error>.Continuation
    private var thread: ConversationThread
    private var assistantID: UUID

    init() {
        let pair = AsyncThrowingStream<ConversationThread, Error>.makeStream()
        self.stream = pair.stream
        self.continuation = pair.continuation
        var thread = ConversationThread(title: "T")
        thread.messages.append(ChatMessage(role: .user, text: "ask"))
        let placeholder = ChatMessage(role: .assistant, text: "", status: .streaming)
        thread.messages.append(placeholder)
        self.thread = thread
        self.assistantID = placeholder.id
    }

    func yieldAssistant(
        text: String,
        thoughtSummary: String? = nil,
        modelResponseParts: [GeminiPartPayload]? = nil,
        status: ChatMessageStatus = .streaming
    ) {
        guard let idx = thread.messages.lastIndex(where: { $0.role == .assistant }) else { return }
        var assistant = thread.messages[idx]
        assistant.text = text
        assistant.thoughtSummary = thoughtSummary
        assistant.modelResponseParts = modelResponseParts
        assistant.status = status
        thread.messages[idx] = assistant
        continuation.yield(thread)
    }

    func finishAssistant(
        text: String,
        status: ChatMessageStatus,
        modelResponseParts: [GeminiPartPayload]? = nil
    ) {
        yieldAssistant(text: text, modelResponseParts: modelResponseParts, status: status)
    }

    func replaceWithFreshAssistant(text: String) {
        // Append a new assistant with a fresh UUID, marking this as a new turn.
        let newAssistant = ChatMessage(role: .assistant, text: text, status: .streaming)
        thread.messages.append(newAssistant)
        assistantID = newAssistant.id
        continuation.yield(thread)
    }

    func fail(_ error: Error) {
        continuation.finish(throwing: error)
    }

    func finish() {
        continuation.finish()
    }
}
