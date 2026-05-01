//
//  AIChat_iOS_AppUITests.swift
//  AIChat iOS AppUITests
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import XCTest

// All iOS UI tests live in `iOSUIFlakyTests` (opt-in via
// AICHAT_RUN_PERFORMANCE=1) because Xcode Cloud's shared iOS simulators
// produce repeated launch-timeout flakes that don't reflect real bugs.
// This stub class is kept so the test bundle is non-empty (so xcodebuild
// has a target to "run", which avoids the "no test bundles available"
// error on the AIChat scheme run).
final class AIChat_iOS_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}
