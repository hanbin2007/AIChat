//
//  PerformanceTestCase.swift
//  AIChat Watch AppTests
//
//  Base class for performance tests. Skipped by default — only runs when
//  `AICHAT_RUN_PERFORMANCE=1` is set in the test process environment.
//
//  Why opt-in:
//  - Wall-clock measurements on Xcode Cloud's shared simulators have huge
//    variance (we've observed 0.35s thresholds blow out to 8.77s under
//    load). Running these on every PR produces false negatives and noise.
//  - These tests are diagnostic baselines, not gates. Run them on a
//    dedicated perf job (a nightly cron, or Xcode Cloud `Performance`
//    workflow type) and observe trends rather than asserting absolutes.
//
//  How to run locally:
//      env AICHAT_RUN_PERFORMANCE=1 \
//          xcodebuild test -scheme "AIChat Watch App" \
//          -destination "platform=watchOS Simulator,id=..." \
//          -only-testing:"AIChat Watch AppTests/ConversationRenderPerformanceTests"
//
//  Baselines: each `measure(metrics:)` call records its own baseline. To
//  set / update, run in Xcode, right-click the diamond, "Set Baseline".
//  Baselines are per-machine and are not committed.
//

import XCTest

class PerformanceTestCase: XCTestCase {
    static let runPerformanceEnvironmentKey = "AICHAT_RUN_PERFORMANCE"

    override func setUpWithError() throws {
        try super.setUpWithError()
        let value = ProcessInfo.processInfo.environment[Self.runPerformanceEnvironmentKey]
        guard value == "1" else {
            throw XCTSkip(
                "Performance tests skipped. Set \(Self.runPerformanceEnvironmentKey)=1 to enable."
            )
        }
    }
}
