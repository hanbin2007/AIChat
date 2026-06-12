//
//  iOSUIFlakyTests.swift
//  AIChat iOS AppUITests
//
//  iOS UI tests that consistently fail on Xcode Cloud's shared iOS
//  simulators (test runner accessibility init timeout, settings sheet
//  scroll geometry variance). Quarantined behind
//  `iOSUIPerformanceTestCase`'s opt-in env var
//  (`AICHAT_RUN_PERFORMANCE=1`) to keep PR CI clean.
//

import XCTest

final class iOSUIFlakyTests: iOSUIPerformanceTestCase {

    @MainActor
    func testImageAttachmentRendersAndOpensViewer() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_image_attachment"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion image detail hierarchy")
            XCTFail("The companion image conversation did not open.")
            return
        }

        let attachment = app.descendants(matching: .any)["message.attachment.00000000-0000-0000-0000-000000000413"]
        if !attachment.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion image attachment hierarchy")
            XCTFail("The companion message attachment did not render.")
            return
        }

        if revealElementIfNeeded(attachment, in: detail) == false {
            attachDebugHierarchy(app, named: "Companion image attachment never became hittable")
            XCTFail("The companion message attachment did not become tappable.")
            return
        }

        attachment.tap()

        let viewer = app.descendants(matching: .any)["message.attachment-viewer"]
        if !viewer.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing companion image viewer hierarchy")
            XCTFail("The image attachment viewer did not open.")
            return
        }

        attachScreenshot(app, named: "companion-image-viewer")
    }

    @MainActor
    func testHeavyMarkdownConversationRendersWithoutBlockingInitialLoad() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_heavy_markdown"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion detail hierarchy")
            XCTFail("The companion conversation detail view did not appear.")
            return
        }

        let expandButton = app.buttons["展开全文"].firstMatch
        if !expandButton.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing heavy markdown expand button hierarchy")
            XCTFail("The heavy markdown conversation did not finish its initial collapsed render.")
            return
        }

        XCTAssertTrue(waitForHittable(expandButton, timeout: 5))
        XCTAssertEqual(expandButton.label, "展开全文")

        expandButton.tap()

        let collapseButton = app.buttons["收起全文"].firstMatch
        XCTAssertTrue(collapseButton.waitForExistence(timeout: 10))
        XCTAssertEqual(collapseButton.label, "收起全文")

        attachScreenshot(app, named: "companion-heavy-markdown-expanded")
    }

    @MainActor
    func testReadOnlyCompanionConversationCanStillBeDeleted() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_delete_read_only"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing read-only companion detail hierarchy")
            XCTFail("The read-only companion conversation detail did not appear.")
            return
        }

        let settingsButton = app.buttons["conversation.settings.open"].firstMatch
        if !settingsButton.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing read-only companion settings button hierarchy")
            XCTFail("The settings entry did not appear for the read-only companion conversation.")
            return
        }
        XCTAssertTrue(waitForHittable(settingsButton, timeout: 5))
        settingsButton.tap()

        let settingsView = app.descendants(matching: .any)["companion.conversation.settings"].firstMatch
        if !settingsView.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing read-only companion settings form hierarchy")
            XCTFail("The settings form did not appear for the read-only companion conversation.")
            return
        }

        let deleteButton = app.descendants(matching: .any)["companion.conversation.settings.delete"].firstMatch
        if revealElementIfNeeded(deleteButton, in: settingsView) == false {
            attachDebugHierarchy(app, named: "Missing read-only companion settings delete hierarchy")
            XCTFail("The delete action did not become visible in read-only companion settings.")
            return
        }

        XCTAssertTrue(waitForHittable(deleteButton, timeout: 5))
        deleteButton.tap()

        let alert = app.alerts["删除会话？"].firstMatch
        if !alert.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing companion delete confirmation hierarchy")
            XCTFail("Deleting from companion settings did not show a confirmation alert.")
            return
        }

        attachScreenshot(app, named: "companion-conversation-settings-delete-confirmation")
        alert.buttons["删除会话"].tap()

        let notFoundState = app.descendants(matching: .any)["companion.conversation.not-found"].firstMatch
        let emptySelectionState = app.descendants(matching: .any)["companion.empty-selection"].firstMatch
        XCTAssertTrue(
            notFoundState.waitForExistence(timeout: 2) ||
            emptySelectionState.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // `XCTApplicationLaunchMetric` requires multiple successful launches
        // to compute a baseline; on Xcode Cloud's shared iOS simulators we
        // see "Received unexpected number of metrics: 0 in iteration..."
        // when individual launches fail to complete. Same opt-in gate as
        // the rest of this suite.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Helpers (copied from AIChat_iOS_AppUITests so the suite is self-contained)

    @MainActor
    private func revealElementIfNeeded(
        _ element: XCUIElement,
        in container: XCUIElement,
        timeout: TimeInterval = 15
    ) -> Bool {
        if waitForHittable(element, timeout: 1) {
            return true
        }

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
