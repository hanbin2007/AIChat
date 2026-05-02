//
//  iOSUIPerformanceTestCase.swift
//  AIChat iOS AppUITests
//
//  Base class for iOS UI tests that are skipped on default CI runs and
//  only execute when `AICHAT_RUN_PERFORMANCE=1` is set in the test
//  process environment. Mirrors the watch-side `UIPerformanceTestCase`.
//
//  Used both for actual performance tests (launch metric, etc.) and for
//  the chronically-flaky cloud-simulator scenarios that produce noise
//  on every PR.
//

import XCTest

class iOSUIPerformanceTestCase: XCTestCase {
    static let runPerformanceEnvironmentKey = "AICHAT_RUN_PERFORMANCE"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let value = ProcessInfo.processInfo.environment[Self.runPerformanceEnvironmentKey]
        guard value == "1" else {
            throw XCTSkip(
                "iOS UI performance / opt-in tests skipped. Set \(Self.runPerformanceEnvironmentKey)=1 to enable."
            )
        }
    }
}
