//
//  LaunchSmokeTests.swift
//  AIChat Watch AppUITests
//
//  Minimal placeholder UI test — confirms the rewritten app launches
//  without crashing and the placeholder shell appears. The full UI
//  test matrix gets re-authored in the UI redesign phase, when the
//  shell is replaced by the real interface.
//

import XCTest

final class LaunchSmokeTests: XCTestCase {

    @MainActor
    func test_launchesAndRendersPlaceholderShell() async throws {
        let app = XCUIApplication()
        app.launch()
        // Tabs we expose in `PlaceholderShell`.
        let exists = app.staticTexts["Chats"].waitForExistence(timeout: 10) ||
                     app.staticTexts["Activation"].waitForExistence(timeout: 10) ||
                     app.staticTexts["Billing"].waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "expected placeholder shell to render at least one tab title")

        // Capture a screenshot for the ASC bridge.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "placeholder-shell"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
