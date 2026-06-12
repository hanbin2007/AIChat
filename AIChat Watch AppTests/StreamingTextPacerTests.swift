//
//  StreamingTextPacerTests.swift
//  AIChat Watch AppTests
//
//  Regression tests for the frame-synced streaming reveal pacer. These
//  pin the contract that:
//    1. Buffered deltas are revealed in order.
//    2. `finalize()` guarantees pixels match the full buffer before it
//       returns (so the caller can safely flip message status).
//    3. `cancel()` commits buffered text immediately — used on error.
//    4. `setPaused(true)` halts reveals; on resume the ticker catches up.
//    5. Appending after `cancel()`/before `begin()` is a no-op.
//
//  Scroll jank on watchOS used to come from `@Published conversations`
//  mutating every 120ms during streaming. The pacer replaces that path
//  for visible text; if any of the above invariants break we lose either
//  correctness or the perf win — hence these tests.
//

import XCTest
@testable import AIChat_Watch_App

final class StreamingTextPacerTests: XCTestCase {

    // NOTE: All tests here are `async throws` even when the logic doesn't
    // require it. The watchOS 26 test runner has a launch-race bug where
    // the first sync @MainActor test per process segfaults the app host
    // while async ones survive. Keeping every test async works around it
    // and also makes the file consistent.

    @MainActor
    func testBeginResetsRevealedState() async throws {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        let messageID = UUID()

        pacer.begin(messageID: messageID)

        XCTAssertEqual(pacer.targetMessageID, messageID)
        XCTAssertTrue(pacer.isActive)
        XCTAssertEqual(pacer.revealedText, "")
        XCTAssertEqual(pacer.revealedThoughtSummary, "")
    }

    @MainActor
    func testAppendWithoutBeginIsNoOp() async throws {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.appendAnswer("should be ignored")
        pacer.appendThoughtSummary("also ignored")

        XCTAssertEqual(pacer.revealedText, "")
        XCTAssertEqual(pacer.revealedThoughtSummary, "")
        XCTAssertFalse(pacer.isActive)
    }

    @MainActor
    func testFinalizeRevealsAllBufferedAnswer() async {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.appendAnswer("Hello, ")
        pacer.appendAnswer("streaming ")
        pacer.appendAnswer("world")

        await pacer.finalize()

        XCTAssertEqual(pacer.revealedText, "Hello, streaming world")
        XCTAssertFalse(pacer.isActive)
    }

    @MainActor
    func testFinalizeRevealsAllBufferedThoughtSummary() async {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.appendThoughtSummary("thinking...")
        pacer.appendThoughtSummary(" more thought")

        await pacer.finalize()

        XCTAssertEqual(pacer.revealedThoughtSummary, "thinking... more thought")
    }

    @MainActor
    func testCancelCommitsBufferedTextImmediately() async throws {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.appendAnswer("partial text")
        pacer.appendThoughtSummary("partial thought")

        pacer.cancel()

        XCTAssertEqual(pacer.revealedText, "partial text")
        XCTAssertEqual(pacer.revealedThoughtSummary, "partial thought")
        XCTAssertFalse(pacer.isActive)
    }

    @MainActor
    func testPauseHaltsRevealResumeCatchesUp() async {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.setPaused(true)
        pacer.appendAnswer("pending while paused")

        // Wait a few tick intervals to prove paused ticker does nothing.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(pacer.revealedText, "")

        pacer.setPaused(false)
        await pacer.finalize()

        XCTAssertEqual(pacer.revealedText, "pending while paused")
    }

    @MainActor
    func testFinalizeBypassesPausedState() async {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.appendAnswer("buffered content")
        pacer.setPaused(true)

        // finalize() must resolve even while paused — callers rely on it
        // to flush the final text before flipping bubble state.
        await pacer.finalize()

        XCTAssertEqual(pacer.revealedText, "buffered content")
        XCTAssertFalse(pacer.isActive)
    }

    @MainActor
    func testBufferedAccessorsReflectLatestDeltas() async throws {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        pacer.appendAnswer("full answer buffer")
        pacer.appendThoughtSummary("full thought buffer")

        // The reveal may still be in-flight, but the buffered snapshot must
        // be immediately available (used by error-recovery + persistence).
        XCTAssertEqual(pacer.bufferedAnswerText, "full answer buffer")
        XCTAssertEqual(pacer.bufferedThoughtText, "full thought buffer")
    }

    @MainActor
    func testRevealAfterBeginTargetSwitchDoesNotLeakPriorBuffer() async {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        let firstID = UUID()
        let secondID = UUID()

        pacer.begin(messageID: firstID)
        pacer.appendAnswer("first reply")
        await pacer.finalize()
        XCTAssertEqual(pacer.revealedText, "first reply")

        pacer.begin(messageID: secondID)
        XCTAssertEqual(pacer.revealedText, "")
        XCTAssertEqual(pacer.targetMessageID, secondID)

        pacer.appendAnswer("second reply")
        await pacer.finalize()
        XCTAssertEqual(pacer.revealedText, "second reply")
    }

    @MainActor
    func testStressBurstRevealsEntireBuffer() async throws {
        // Simulates the "relay finishes a huge response in one SSE frame"
        // case: 10k chars shoved at the pacer in a single append. Finalize
        // must drain all of it, and the adaptive rate must pick the
        // overflow-drain path without starving.
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        let burst = String(repeating: "x", count: 10_000)
        pacer.appendAnswer(burst)

        await pacer.finalize()
        XCTAssertEqual(pacer.revealedText.count, 10_000)
        XCTAssertEqual(pacer.revealedText, burst)
    }

    @MainActor
    func testStressHighRateSustainedAppend() async throws {
        // Simulates a model streaming 1-char tokens at 1kHz for 1 second.
        // The pacer must not drop characters and must finalize with the
        // full sequence intact.
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        let iterations = 1_000
        for index in 0..<iterations {
            pacer.appendAnswer(String(index % 10))
        }

        await pacer.finalize()
        let expected = (0..<iterations).map { String($0 % 10) }.joined()
        XCTAssertEqual(pacer.revealedText, expected)
    }

    @MainActor
    func testStressRapidPauseResumeDoesNotLoseCharacters() async throws {
        // A jittery user dragging in short bursts toggles pause/resume
        // many times while the pacer is actively revealing. Every
        // character that landed in the buffer must reach the reveal even
        // if toggling happens mid-tick.
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        for index in 0..<200 {
            pacer.appendAnswer("a")
            if index.isMultiple(of: 3) {
                pacer.setPaused(true)
                pacer.setPaused(false)
            }
        }

        await pacer.finalize()
        XCTAssertEqual(pacer.revealedText.count, 200)
    }

    @MainActor
    func testStressConcurrentAnswerAndThoughtDrain() async throws {
        // Both channels active simultaneously — the tick should distribute
        // reveal bandwidth across them rather than starving one.
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        let answer = String(repeating: "A", count: 500)
        let thought = String(repeating: "T", count: 500)

        pacer.appendAnswer(answer)
        pacer.appendThoughtSummary(thought)

        await pacer.finalize()
        XCTAssertEqual(pacer.revealedText, answer)
        XCTAssertEqual(pacer.revealedThoughtSummary, thought)
    }

    @MainActor
    func testGraphemeClustersStayIntact() async {
        // Reveal must never split extended grapheme clusters — a composed
        // emoji or zero-width joiner sequence must not appear as half a
        // glyph mid-reveal. Swift's `String.prefix(n)` treats count as
        // grapheme count, so this also guards against accidental
        // regression to UTF-16 indexing.
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        let input = "👨‍👩‍👧‍👦 family + 你好"
        pacer.appendAnswer(input)
        await pacer.finalize()

        XCTAssertEqual(pacer.revealedText, input)
    }

    @MainActor
    func testLongUnicodeRevealDoesNotRescanFromBufferStartEachTick() async throws {
        let pacer = StreamingTextPacer(configuration: .fastTestConfiguration)
        pacer.begin(messageID: UUID())

        let input = String(repeating: "👨‍👩‍👧‍👦 cafe\u{301} 你好 ", count: 12_000)
        pacer.appendAnswer(input)

        let start = CFAbsoluteTimeGetCurrent()
        pacer.revealSynchronouslyForTesting(maxChunkSize: 1)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(pacer.revealedText, input)
        XCTAssertLessThan(elapsed, 0.35)
    }
}

private extension StreamingTextPacer.Configuration {
    /// Aggressively short tick interval so tests don't sit waiting on the
    /// adaptive 30Hz pacing. Keeps suite fast without changing semantics.
    static var fastTestConfiguration: StreamingTextPacer.Configuration {
        StreamingTextPacer.Configuration(
            tickInterval: 0.001,
            drainOverflowThreshold: 10,
            onReveal: nil
        )
    }
}
