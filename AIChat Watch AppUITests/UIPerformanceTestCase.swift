//
//  UIPerformanceTestCase.swift
//  AIChat Watch AppUITests
//
//  Base class for UI-level performance and hang-detection tests. Skipped
//  by default — only runs when `AICHAT_RUN_PERFORMANCE=1` is set in the
//  test process environment.
//
//  Why opt-in:
//  - Wall-clock measurements and the hang monitor on Xcode Cloud's shared
//    simulators have huge variance. Running these on every PR produces
//    false negatives and noise (we observed 8 spurious hang events on
//    history list scroll on a 0-tolerance gate).
//  - These tests are diagnostic baselines, not gates. Run them on a
//    dedicated perf job (a nightly cron, or Xcode Cloud `Performance`
//    workflow type) and observe trends rather than asserting absolutes.
//
//  How to run locally:
//      env AICHAT_RUN_PERFORMANCE=1 \
//          xcodebuild test -scheme "AIChat Watch UITests" \
//          -destination "platform=watchOS Simulator,id=..." \
//          -only-testing:"AIChat Watch AppUITests/WatchUIPerformanceTests"
//

import XCTest

class UIPerformanceTestCase: XCTestCase {
    static let runPerformanceEnvironmentKey = "AICHAT_RUN_PERFORMANCE"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let value = ProcessInfo.processInfo.environment[Self.runPerformanceEnvironmentKey]
        guard value == "1" else {
            throw XCTSkip(
                "UI performance tests skipped. Set \(Self.runPerformanceEnvironmentKey)=1 to enable."
            )
        }
    }
}
