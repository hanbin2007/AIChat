//
//  AIChat_iOS_AppUITests.swift
//  AIChat iOS AppUITests
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import XCTest

// Default iOS UI smoke tests live here. Chronically flaky or performance-only
// scenarios stay in `iOSUIFlakyTests` behind AICHAT_RUN_PERFORMANCE=1.
final class AIChat_iOS_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompanionGlobalSettingsExposeAutoScrollToggle() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        let settingsButton = app.buttons["companion.global-settings.open"].firstMatch
        if !settingsButton.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion global settings button hierarchy")
            XCTFail("The companion global settings button did not appear.")
            return
        }

        XCTAssertTrue(waitForHittable(settingsButton, timeout: 5))
        settingsButton.tap()

        let autoScrollToggle = app.switches["companion.settings.auto-scroll"].firstMatch
        if !autoScrollToggle.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing companion auto-scroll setting hierarchy")
            XCTFail("The companion global settings sheet did not expose auto-scroll.")
            return
        }

        attachScreenshot(app, named: "companion-global-settings-auto-scroll")
    }

    @MainActor
    func testCompanionDraftImageAttachmentShowsContrastingRemoveControl() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "companion_draft_image_attachment"
        app.launch()

        let detail = app.scrollViews["companion.conversation.detail"].firstMatch
        if !detail.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion draft attachment detail hierarchy")
            XCTFail("The companion draft attachment conversation did not open.")
            return
        }

        let attachmentPreview = app.descendants(matching: .any)["conversation.draft-attachment.preview"].firstMatch
        if !attachmentPreview.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing companion draft attachment preview hierarchy")
            XCTFail("The companion draft attachment preview did not render.")
            return
        }

        let removeButton = app.buttons["conversation.draft-attachment.remove"].firstMatch
        if !removeButton.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing companion draft attachment remove button hierarchy")
            XCTFail("The companion draft attachment remove control did not render.")
            return
        }

        attachScreenshot(app, named: "companion-draft-image-attachment-remove-control")
    }
}
