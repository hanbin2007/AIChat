//
//  AIChat_iOS_AppUITests.swift
//  AIChat iOS AppUITests
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import XCTest

final class AIChat_iOS_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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
