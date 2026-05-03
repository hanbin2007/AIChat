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

        // The slow streaming service emits "智能" as the very first chunk.
        // Once that label exists, the assistant bubble has at least 2
        // characters in the trailing fade window — enough to read the
        // gradient + the cursor in a single screenshot.
        let firstChunk = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "智能"))
            .firstMatch
        if !firstChunk.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Streaming fade-in first chunk never appeared")
            XCTFail("The streaming reply never rendered the seed chunk; the fade-in cannot be screenshotted.")
            return
        }

        // Sit on the running stream for ~33ms (half a 15Hz pacer tick) so we
        // catch the bubble mid-reveal instead of right at a text-update
        // boundary, which would show a fully-opaque trailing edge.
        Thread.sleep(forTimeInterval: 0.033)
        attachScreenshot(app, named: "companion-streaming-fade-in-mid-stream")

        // Take a second shot ~1s later. The trailing-edge gradient should
        // have walked further into the message.
        Thread.sleep(forTimeInterval: 1.0)
        attachScreenshot(app, named: "companion-streaming-fade-in-later")
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

        // Issue #32 fix: on compact size class the post-delete reconciler
        // must NOT auto-jump into the neighbor conversation. The neighbor
        // exists in the seed (`compactDeletePair`) precisely so this would
        // regress to "auto-jumped into it" if the size-class branch were
        // dropped from `CompanionSelectionReconciler`.
        let emptySelectionState = app.descendants(matching: .any)["companion.empty-selection"].firstMatch
        XCTAssertTrue(
            emptySelectionState.waitForExistence(timeout: 8),
            "After deleting the open conversation on iPhone, the empty-selection placeholder must appear instead of another conversation auto-loading."
        )

        attachScreenshot(app, named: "companion-compact-delete-pops-to-list")
    }

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

        let gestures: [(XCUIElement) -> Void] = Array(
            repeating: { $0.swipeUp() },
            count: 6
        ) + [
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
