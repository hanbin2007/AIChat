//
//  ConversationAutoScrollControllerTests.swift
//  AIChat Watch AppTests
//
//  Unit tests for the shared auto-scroll state machine. Previously tested
//  only indirectly via UI scenarios — this file pins the behaviour
//  directly so perf work around streaming/scroll can't silently change
//  it.
//
//  The state machine has one subtle rule: when a new streaming session
//  starts, scroll interruptions are suppressed for a short window (to
//  avoid the first few scroll-geometry frames being misread as a user
//  drag). The tests below pin that window's behaviour explicitly because
//  regressions here surface as "the first auto-scroll never fires".
//
//  All tests declared `async throws` — the watchOS 26 test runner has a
//  launch-race bug where the first sync @MainActor test per process
//  segfaults the app host. Keeping every test async works around it.
//

import XCTest
@testable import AIChat_Watch_App

final class ConversationAutoScrollControllerTests: XCTestCase {

    @MainActor
    func testShouldAutoScrollFollowsInterruptedFlag() async throws {
        var state = ConversationAutoScrollState()
        XCTAssertTrue(ConversationAutoScrollController.shouldAutoScroll(state: state))

        state.isInterrupted = true
        XCTAssertFalse(ConversationAutoScrollController.shouldAutoScroll(state: state))
    }

    @MainActor
    func testHandleStreamingMessageChangeActivatesSession() async throws {
        var state = ConversationAutoScrollState()
        state.isInterrupted = true
        state.interruptedSessionMessageID = UUID()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000)
        let newMessageID = UUID()

        ConversationAutoScrollController.handleStreamingMessageChange(
            state: &state,
            latestAssistantMessageID: newMessageID,
            previousSessionMessageID: nil,
            now: fixedNow
        )

        XCTAssertEqual(state.activeSessionMessageID, newMessageID)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertNil(state.interruptedSessionMessageID)
        XCTAssertNil(state.suspendedStreamingRenderMessageID)
        // Suppression window extends ~0.6s past `now`.
        XCTAssertEqual(
            state.scrollInterruptionsSuppressedUntil.timeIntervalSince(fixedNow),
            0.6,
            accuracy: 0.001
        )
    }

    @MainActor
    func testHandleStreamingMessageChangeIgnoresUnchangedID() async throws {
        var state = ConversationAutoScrollState()
        let messageID = UUID()
        state.activeSessionMessageID = messageID
        state.isInterrupted = true
        state.scrollInterruptionsSuppressedUntil = Date.distantPast

        ConversationAutoScrollController.handleStreamingMessageChange(
            state: &state,
            latestAssistantMessageID: messageID,
            previousSessionMessageID: messageID
        )

        // Same ID → no state mutation (including the suppression window
        // staying in the past — we don't want to grant suppression for an
        // unchanged message).
        XCTAssertTrue(state.isInterrupted)
        XCTAssertEqual(state.scrollInterruptionsSuppressedUntil, .distantPast)
    }

    @MainActor
    func testHandleStreamingMessageChangeClearsSessionWhenNoAssistantExists() async throws {
        var state = ConversationAutoScrollState()
        state.activeSessionMessageID = UUID()
        state.isInterrupted = true
        state.interruptedSessionMessageID = state.activeSessionMessageID
        state.suspendedStreamingRenderMessageID = state.activeSessionMessageID

        ConversationAutoScrollController.handleStreamingMessageChange(
            state: &state,
            latestAssistantMessageID: nil,
            previousSessionMessageID: nil
        )

        XCTAssertNil(state.activeSessionMessageID)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertNil(state.interruptedSessionMessageID)
        XCTAssertNil(state.suspendedStreamingRenderMessageID)
    }

    @MainActor
    func testInterruptAutoScrollRespectsSuppressionWindow() async throws {
        var state = ConversationAutoScrollState()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000)
        state.scrollInterruptionsSuppressedUntil = fixedNow.addingTimeInterval(0.5)

        ConversationAutoScrollController.interruptAutoScroll(state: &state, now: fixedNow)

        // Inside suppression window → interrupt is ignored.
        XCTAssertFalse(state.isInterrupted)
    }

    @MainActor
    func testInterruptAutoScrollFiresAfterSuppressionWindow() async throws {
        var state = ConversationAutoScrollState()
        let activeID = UUID()
        state.activeSessionMessageID = activeID
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000)
        state.scrollInterruptionsSuppressedUntil = fixedNow.addingTimeInterval(-0.1)

        ConversationAutoScrollController.interruptAutoScroll(state: &state, now: fixedNow)

        XCTAssertTrue(state.isInterrupted)
        XCTAssertEqual(state.interruptedSessionMessageID, activeID)
    }

    @MainActor
    func testInterruptAutoScrollImmediatelyBypassesSuppressionWindow() async throws {
        var state = ConversationAutoScrollState()
        let activeID = UUID()
        state.activeSessionMessageID = activeID
        state.scrollInterruptionsSuppressedUntil = Date.distantFuture

        ConversationAutoScrollController.interruptAutoScrollImmediately(state: &state)

        XCTAssertTrue(state.isInterrupted)
        XCTAssertEqual(state.interruptedSessionMessageID, activeID)
    }

    @MainActor
    func testInterruptAutoScrollIsIdempotent() async throws {
        var state = ConversationAutoScrollState()
        let activeID = UUID()
        let interruptedID = UUID()
        state.activeSessionMessageID = activeID
        state.isInterrupted = true
        state.interruptedSessionMessageID = interruptedID
        // Both suppress-window scenarios shouldn't clobber an already-set
        // interruptedSessionMessageID — that carries UI meaning.
        ConversationAutoScrollController.interruptAutoScroll(state: &state, now: .now)
        XCTAssertEqual(state.interruptedSessionMessageID, interruptedID)

        ConversationAutoScrollController.interruptAutoScrollImmediately(state: &state)
        XCTAssertEqual(state.interruptedSessionMessageID, interruptedID)
    }

    @MainActor
    func testSuspendStreamingRenderImpliesImmediateInterrupt() async throws {
        var state = ConversationAutoScrollState()
        let activeID = UUID()
        state.activeSessionMessageID = activeID
        state.scrollInterruptionsSuppressedUntil = Date.distantFuture

        ConversationAutoScrollController.suspendStreamingRender(state: &state, for: activeID)

        XCTAssertTrue(state.isInterrupted)
        XCTAssertEqual(state.interruptedSessionMessageID, activeID)
        XCTAssertEqual(state.suspendedStreamingRenderMessageID, activeID)
    }

    @MainActor
    func testSuspendStreamingRenderWithNilIDIsNoOp() async throws {
        var state = ConversationAutoScrollState()
        ConversationAutoScrollController.suspendStreamingRender(state: &state, for: nil)

        XCTAssertFalse(state.isInterrupted)
        XCTAssertNil(state.suspendedStreamingRenderMessageID)
    }

    @MainActor
    func testScheduleStreamingRenderResumeCancelsPreviousTask() async throws {
        var task: Task<Void, Never>?
        var resumeFiredA = false
        var resumeFiredB = false

        ConversationAutoScrollController.scheduleStreamingRenderResume(
            suspendedMessageID: UUID(),
            currentTask: &task,
            onResume: { resumeFiredA = true },
            delay: 0.05
        )

        // Immediately schedule a replacement — the first task must cancel
        // so its onResume never fires (otherwise we'd get double-resume).
        ConversationAutoScrollController.scheduleStreamingRenderResume(
            suspendedMessageID: UUID(),
            currentTask: &task,
            onResume: { resumeFiredB = true },
            delay: 0.05
        )

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(resumeFiredA, "first scheduler should have been cancelled")
        XCTAssertTrue(resumeFiredB, "latest scheduler should have resumed")
    }

    @MainActor
    func testScheduleStreamingRenderResumeSkipsWhenMessageIDNil() async throws {
        var task: Task<Void, Never>?
        var fired = false

        ConversationAutoScrollController.scheduleStreamingRenderResume(
            suspendedMessageID: nil,
            currentTask: &task,
            onResume: { fired = true },
            delay: 0.01
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(fired)
        XCTAssertNil(task)
    }
}
