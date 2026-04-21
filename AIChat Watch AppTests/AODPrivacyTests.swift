//
//  AODPrivacyTests.swift
//  AIChat Watch AppTests
//
//  Verifies the Always-On Display privacy contract: the watch app Info.plist
//  opts into AOD (so the system injects `\.redactionReasons = .privacy` on
//  wrist-down) which, combined with `.privacySensitive()` modifiers on
//  chat/conversation/composer surfaces, lets the system redact sensitive
//  content automatically.
//
//  Tests are `async throws` per CLAUDE.md (watchOS 26 has a test-runner
//  launch race that segfaults the first sync `@MainActor` test per process).
//
//  Caveat: watchOS simulator does not expose a deterministic AOD simulation
//  hook, so we cannot assert "the pixels are redacted" at unit-test level.
//  The plist check below locks the AOD opt-in; on-device manual verification
//  remains the authoritative check for `.privacySensitive()` coverage.
//

import SwiftUI
import XCTest
@testable import AIChat_Watch_App

final class AODPrivacyTests: XCTestCase {
    /// The Info.plist must advertise `WKSupportsAlwaysOnDisplay = true`.
    /// Without this key, watchOS never activates AOD for the app and
    /// `.privacySensitive()` modifiers elsewhere are dead. This assertion
    /// locks the plist wiring so a future refactor can't silently drop the
    /// key and break the privacy contract.
    @MainActor
    func testWatchAppInfoPlistOptsIntoAlwaysOnDisplay() async throws {
        // We read the *host* app bundle via an app-side type. XCTest on
        // watchOS hosts the test bundle inside the watch app; `Bundle(for:)`
        // on an `@testable`-imported type resolves to the app bundle itself.
        let watchAppBundle = Bundle(for: ChatStore.self)

        guard let infoDictionary = watchAppBundle.infoDictionary else {
            XCTFail("Watch app bundle is missing an Info.plist dictionary.")
            return
        }

        guard let rawValue = infoDictionary["WKSupportsAlwaysOnDisplay"] else {
            XCTFail("""
                Watch app Info.plist is missing `WKSupportsAlwaysOnDisplay`. \
                Without this key, watchOS never activates Always-On Display \
                for the app and `.privacySensitive()` modifiers applied to \
                chat content cannot be triggered by the system.
                """)
            return
        }

        if let boolValue = rawValue as? Bool {
            XCTAssertTrue(
                boolValue,
                "`WKSupportsAlwaysOnDisplay` must be `true` to enable Always-On Display redaction."
            )
            return
        }

        if let numberValue = rawValue as? NSNumber {
            XCTAssertTrue(
                numberValue.boolValue,
                "`WKSupportsAlwaysOnDisplay` must be `true` to enable Always-On Display redaction."
            )
            return
        }

        XCTFail(
            "`WKSupportsAlwaysOnDisplay` has an unexpected value type: \(type(of: rawValue))"
        )
    }
}
