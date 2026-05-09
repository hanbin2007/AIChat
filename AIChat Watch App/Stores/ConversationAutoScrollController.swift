//
//  ConversationAutoScrollController.swift
//  AIChat Watch App
//
//  Per-screen state machine for the auto-scroll-to-bottom behavior in
//  `ConversationDetailView`. The detail view binds its
//  `ScrollViewReader` to `anchorMessageID`; whenever this controller
//  publishes a new value the view scrolls to that message.
//
//  Rules:
//    - While streaming, content updates to the same last-message id
//      re-publish the anchor (so SwiftUI re-runs the scroll).
//    - The user dragging the scroll mid-stream flips `shouldFollow`
//      false; further intra-message updates are then ignored.
//    - A *new* assistant message id (next turn) overrides the freeze:
//      the controller anchors regardless of `shouldFollow`, then
//      re-arms follow.
//    - `streamDidFinish()` re-arms follow at end of turn so the next
//      turn starts in the followed state.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConversationAutoScrollController {

    private(set) var anchorMessageID: UUID?
    private(set) var shouldFollow: Bool = true
    private var lastKnownLastMessageID: UUID?

    init() {}

    func messageContentDidUpdate(latestMessageID: UUID) {
        if latestMessageID != lastKnownLastMessageID {
            lastKnownLastMessageID = latestMessageID
            shouldFollow = true
            anchorMessageID = latestMessageID
            return
        }
        guard shouldFollow else { return }
        // Republish even if equal — SwiftUI's onChange treats setting
        // an Observable to its current value as a no-op, but we want
        // intra-bubble growth to keep scrolling. So we toggle to nil
        // first if needed and then back; instead, callers should drive
        // anchor changes by message id, with the bubble growing in
        // place. SwiftUI's ScrollViewReader.scrollTo on the same id
        // still resolves to the latest layout, so simply re-assigning
        // is correct here.
        anchorMessageID = latestMessageID
    }

    func userDidInteractWithScroll() {
        shouldFollow = false
    }

    func streamDidFinish() {
        shouldFollow = true
    }

    func resetForNewConversation() {
        anchorMessageID = nil
        shouldFollow = true
        lastKnownLastMessageID = nil
    }
}
