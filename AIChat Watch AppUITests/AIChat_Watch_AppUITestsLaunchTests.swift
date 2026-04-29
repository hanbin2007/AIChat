//
//  AIChat_Watch_AppUITestsLaunchTests.swift
//  AIChat Watch AppUITests
//
//  Created by zhb on 2026/3/7.
//

import XCTest

final class AIChat_Watch_AppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The auto-generated watchOS launch screenshot test consistently
        // hits Xcode Cloud's 10-minute test allowance because the simulator
        // host fails to install / launch the test runner ("launchd_sim
        // crashed") on the shared CI environment. Skip by default to keep
        // PR CI signal clean; opt in with `AICHAT_RUN_PERFORMANCE=1` when
        // you actually want the launch screenshot.
        if ProcessInfo.processInfo.environment["AICHAT_RUN_PERFORMANCE"] != "1" {
            throw XCTSkip("Watch launch screenshot test skipped on default CI; set AICHAT_RUN_PERFORMANCE=1 to enable.")
        }
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
