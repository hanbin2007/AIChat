//
//  ConversationAutoScrollController.swift
//  AIChat Watch App
//
//  Shared auto-scroll state machine used by both ConversationDetailView
//  (watchOS) and CompanionConversationDetailView (iOS).
//

import Foundation

struct ConversationAutoScrollState: Equatable {
    var isInterrupted = false
    var activeSessionMessageID: UUID?
    var interruptedSessionMessageID: UUID?
    var suspendedStreamingRenderMessageID: UUID?
    var completedReplyMessageID: UUID?
    var scrollInterruptionsSuppressedUntil = Date.distantPast
}

enum ConversationAutoScrollController {

    static func shouldAutoScroll(state: ConversationAutoScrollState) -> Bool {
        state.isInterrupted == false
    }

    static func handleStreamingMessageChange(
        state: inout ConversationAutoScrollState,
        latestAssistantMessageID: UUID?,
        previousSessionMessageID: UUID?,
        now: Date = .now
    ) {
        guard let latestAssistantMessageID else {
            if state.activeSessionMessageID != nil {
                state.activeSessionMessageID = nil
                state.isInterrupted = false
                state.interruptedSessionMessageID = nil
                state.suspendedStreamingRenderMessageID = nil
            }
            return
        }

        guard latestAssistantMessageID != previousSessionMessageID else {
            return
        }

        state.activeSessionMessageID = latestAssistantMessageID
        state.isInterrupted = false
        state.interruptedSessionMessageID = nil
        state.suspendedStreamingRenderMessageID = nil
        state.scrollInterruptionsSuppressedUntil = now.addingTimeInterval(0.6)
    }

    static func interruptAutoScroll(
        state: inout ConversationAutoScrollState,
        now: Date = .now
    ) {
        guard now >= state.scrollInterruptionsSuppressedUntil else {
            return
        }
        guard state.isInterrupted == false else {
            return
        }
        state.isInterrupted = true
        state.interruptedSessionMessageID = state.activeSessionMessageID
    }

    static func interruptAutoScrollImmediately(
        state: inout ConversationAutoScrollState
    ) {
        guard state.isInterrupted == false else {
            return
        }
        state.isInterrupted = true
        state.interruptedSessionMessageID = state.activeSessionMessageID
    }

    static func suspendStreamingRender(
        state: inout ConversationAutoScrollState,
        for messageID: UUID?
    ) {
        guard let messageID else { return }
        interruptAutoScrollImmediately(state: &state)
        state.suspendedStreamingRenderMessageID = messageID
    }

    static func scheduleStreamingRenderResume(
        suspendedMessageID: UUID?,
        currentTask: inout Task<Void, Never>?,
        onResume: @escaping @MainActor () -> Void,
        delay: TimeInterval = 1.8
    ) {
        currentTask?.cancel()
        guard suspendedMessageID != nil else {
            return
        }

        let delayNanoseconds = UInt64(delay * 1_000_000_000)
        currentTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard Task.isCancelled == false else { return }
            onResume()
        }
    }
}
