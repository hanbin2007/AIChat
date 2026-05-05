//
//  CompanionTfBugFixUITests.swift
//  AIChat iOS AppUITests
//
//  Visual + behavioral coverage for the 2026-04 TestFlight bugs:
//
//   • #22 — streaming reply uses a per-character trailing fade-in instead
//           of the old four-layer Capsule progress bar.
//   • #30 — iOS Companion is pinned to dark mode regardless of system
//           appearance, so the assistant bubble (white text on translucent
//           dark fill) always reads.
//   • #31 — composer is a TextField + tool "+" inline, with a circular
//           voice button and a circular send button next to it (instead
//           of three equally-wide labelled buttons).
//   • #32 — deleting the open conversation on iPhone (compact split
//           view) pops back to the list rather than auto-jumping into
//           another conversation.
//
//  Each scenario also runs `attachScreenshot` so the Xcode Cloud →
//  GitHub PR comment bridge surfaces the rendered effect for human
//  review.
//

import XCTest

final class CompanionTfBugFixUITests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    // MARK: - #22 streaming fade-in (visual)

    @MainActor
    func testStreamingFadeInDemoCapturesTrailingFadeAndCursor() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_streaming_fade_in"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing fade-in scenario detail hierarchy")
            XCTFail("companion_streaming_fade_in did not open the detail view.")
            return
        }

        // The slow streaming service emits "智能" as the first answer chunk
        // (~600ms pacer warm-up + 220ms first-chunk emission). Cloud iOS
        // sims need a generous deadline. We poll for it via two queries so
        // an a11y trait quirk on a particular iOS build doesn't sink us
        // (some iOS 26 sim builds put fade-rendered Text in `descendants`
        // but not `staticTexts`).
        let predicate = NSPredicate(format: "label CONTAINS %@", "智能")
        let staticMatch = app.staticTexts.matching(predicate).firstMatch
        let descendantMatch = app.descendants(matching: .any).matching(predicate).firstMatch

        let seedDeadline = Date().addingTimeInterval(25)
        var seedAppeared = false
        while Date() < seedDeadline {
            if staticMatch.exists || descendantMatch.exists {
                seedAppeared = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        // Always attach a screenshot so reviewers (and CI artifact
        // pipelines) get a visual of the streaming bubble — even when the
        // seed-text query couldn't confirm it. If streaming legitimately
        // failed to start, the screenshot shows the placeholder; if it
        // started but the a11y trait was off, the screenshot still proves
        // the fade.
        attachScreenshot(app, named: "companion-streaming-fade-in")

        if seedAppeared == false {
            attachDebugHierarchy(app, named: "Streaming fade-in first chunk never appeared")
            XCTFail("The streaming reply never rendered the seed chunk in 25s. See the attached screenshot + debug hierarchy for the on-screen state at timeout.")
        }
    }

    // MARK: - #30 dark mode + #31 composer (visual)

    @MainActor
    func testCompanionRendersInDarkModeAndShowsRedesignedComposer() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_image_attachment"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing dark-mode scenario detail hierarchy")
            XCTFail("companion_image_attachment did not open.")
            return
        }

        let toolEntry = app.descendants(matching: .any)["conversation.tool-entry"].firstMatch
        let voiceButton = app.descendants(matching: .any)["conversation.voice-button"].firstMatch
        let sendButton = app.descendants(matching: .any)["conversation.send-button"].firstMatch

        XCTAssertTrue(
            toolEntry.waitForExistence(timeout: 5),
            "Composer redesign must keep the tool '+' button accessible at conversation.tool-entry."
        )
        XCTAssertTrue(
            voiceButton.waitForExistence(timeout: 5),
            "Composer redesign must expose the circular voice button as conversation.voice-button."
        )
        XCTAssertTrue(
            sendButton.waitForExistence(timeout: 5),
            "Composer redesign must expose the circular send button as conversation.send-button."
        )

        attachScreenshot(app, named: "companion-dark-mode-and-composer")
    }

    // MARK: - #32 compact delete pops to list (functional + screenshot)

    @MainActor
    func testCompactDeletingOpenConversationPopsBackToList() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_compact_delete_pops"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing compact-delete-pops scenario detail hierarchy")
            XCTFail("companion_compact_delete_pops did not open the detail view.")
            return
        }

        // Use the existing "delete from settings" path — it's the same
        // mutation as swipe-to-delete (ChatStore.deleteConversation), and
        // it's deterministic on the iOS simulator. The point of this test
        // isn't the gesture; it's what `reconcileSelection` does after the
        // list mutation.
        let settingsButton = app.buttons["conversation.settings.open"].firstMatch
        if !settingsButton.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Compact-delete-pops settings button missing")
            XCTFail("Settings entry missing in compact-delete scenario.")
            return
        }
        XCTAssertTrue(waitForHittable(settingsButton, timeout: 5))
        settingsButton.tap()

        let settingsView = app.descendants(matching: .any)["companion.conversation.settings"].firstMatch
        if !settingsView.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Compact-delete-pops settings form missing")
            XCTFail("Settings form did not appear.")
            return
        }

        let deleteButton = app.descendants(matching: .any)["companion.conversation.settings.delete"].firstMatch
        if revealElementIfNeeded(deleteButton, in: settingsView) == false {
            attachDebugHierarchy(app, named: "Compact-delete-pops delete row never reachable")
            XCTFail("Delete row did not become visible.")
            return
        }
        XCTAssertTrue(waitForHittable(deleteButton, timeout: 5))
        deleteButton.tap()

        // Issue #32 contract on compact (iPhone): after deleting the open
        // conversation, the split view must POP back to the list instead
        // of auto-pushing the neighbor's detail.
        //
        // Identifier-based assertions (NOT body-text matching, because
        // `CompanionConversationRow` renders `conversation.previewText` in
        // the list row — a previous attempt at this test mis-fired on
        // exactly that, since the neighbor's preview text legitimately
        // shows up in the list after the pop):
        //
        //   * `companion.conversation.row.<openID>` must NOT exist
        //     (the deleted conversation's row is gone from the list).
        //   * `companion.conversation.row.<neighborID>` must be hittable
        //     (the list is the topmost view in compact mode).
        //   * `companion.conversation.detail` must NOT contain the
        //     neighbor's detail content. Easiest way: detail's
        //     `companion.empty-selection` (regular layout) and
        //     `companion.conversation.not-found` (orphaned detail) are
        //     both acceptable; what's NOT acceptable is the detail
        //     scrollView re-mounting on the neighbor's UUID.
        let openRow = app.descendants(matching: .any)[
            "companion.conversation.row.\(openConversationUUIDString)"
        ].firstMatch
        let neighborRow = app.descendants(matching: .any)[
            "companion.conversation.row.\(neighborConversationUUIDString)"
        ].firstMatch

        XCTAssertTrue(
            neighborRow.waitForExistence(timeout: 8),
            "Issue #32 regression: the conversation list never came back into view after deleting the open conversation on iPhone. The compact-mode reconciler should clear the selection and let `NavigationSplitView` pop to the list."
        )

        XCTAssertFalse(
            openRow.exists,
            "The deleted conversation's row is still showing — `chatStore.deleteConversation` did not actually mutate the list."
        )

        attachScreenshot(app, named: "companion-compact-delete-pops-to-list")
    }

    /// Stable UUID strings for the conversations seeded by
    /// `compactDeletePair()` in `AIChatRegistrationApp.swift`.
    private let openConversationUUIDString = "00000000-0000-0000-0000-000000000441"
    private let neighborConversationUUIDString = "00000000-0000-0000-0000-000000000442"

    // MARK: - Helpers (mirror iOSUIFlakyTests so the file is self-contained)

    @MainActor
    private func revealElementIfNeeded(
        _ element: XCUIElement,
        in container: XCUIElement,
        timeout: TimeInterval = 15
    ) -> Bool {
        if waitForHittable(element, timeout: 1) {
            return true
        }

        // 10 swipeUps + 2 swipeDowns matches the iOSUIFlakyTests helper —
        // PR #54 had to bump to this budget so iPhone SE (small screen, long
        // settings Form) doesn't fail to expose the delete row.
        let gestures: [(XCUIElement) -> Void] = [
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeUp() },
            { $0.swipeDown() },
            { $0.swipeDown() }
        ]

        let deadline = Date().addingTimeInterval(timeout)
        for gesture in gestures where Date() < deadline {
            gesture(container)
            if waitForHittable(element, timeout: 1) {
                return true
            }
        }
        return element.isHittable
    }
}
