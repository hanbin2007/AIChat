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
}
