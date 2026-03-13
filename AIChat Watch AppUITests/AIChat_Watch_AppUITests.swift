//
//  AIChat_Watch_AppUITests.swift
//  AIChat Watch AppUITests
//
//  Created by zhb on 2026/3/7.
//

import CoreGraphics
import XCTest

final class AIChat_Watch_AppUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testFormulaCanOpenZoomSheetAndScrollHorizontally() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "formula_zoom"
        app.launch()

        let harness = app.descendants(matching: .any)["formula.zoom.harness"]
        XCTAssertTrue(harness.waitForExistence(timeout: 10))

        let displayFormula = app.descendants(matching: .any)["math.zoom.trigger.display"]
        if !displayFormula.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing block math trigger hierarchy")
            XCTFail("Missing block math trigger.")
            return
        }
        XCTAssertTrue(waitForHittable(displayFormula, timeout: 5))
        displayFormula.tap()

        let zoomSheet = app.descendants(matching: .any)["math.zoom.sheet"]
        if !zoomSheet.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing zoom sheet after block tap hierarchy")
            XCTFail("Missing zoom sheet after tapping block math.")
            return
        }

        let position = app.descendants(matching: .any)["math.zoom.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let initialPosition = accessibilityText(for: position)

        let viewport = app.descendants(matching: .any)["math.zoom.viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 10))
        XCTAssertTrue(rotateCrownUntilValueChanges(of: position, from: initialPosition, focusTarget: viewport))

        let closeButton = app.buttons["math.zoom.close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        XCTAssertFalse(zoomSheet.waitForExistence(timeout: 2))

        let inlineFormula = app.descendants(matching: .any)["math.zoom.trigger.inline"]
        if !inlineFormula.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing inline math trigger hierarchy")
            XCTFail("Missing inline math trigger.")
            return
        }
        XCTAssertTrue(waitForHittable(inlineFormula, timeout: 5))
        inlineFormula.tap()
        if !zoomSheet.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing zoom sheet after inline tap hierarchy")
            XCTFail("Missing zoom sheet after tapping inline math.")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func waitForValueChange(
        of element: XCUIElement,
        from originalValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if accessibilityText(for: element) != originalValue {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return accessibilityText(for: element) != originalValue
    }

    @MainActor
    private func waitForHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.isHittable
    }

    @MainActor
    private func rotateCrownUntilValueChanges(
        of element: XCUIElement,
        from originalValue: String,
        focusTarget: XCUIElement
    ) -> Bool {
        let crownDeltas: [CGFloat] = [0.35, 0.7, 1.0]

        for delta in crownDeltas {
            if focusTarget.exists {
                focusTarget.tap()
            }

            XCUIDevice.shared.rotateDigitalCrown(delta: delta)

            if waitForValueChange(of: element, from: originalValue, timeout: 2) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func accessibilityText(for element: XCUIElement) -> String {
        if element.label.isEmpty == false {
            return element.label
        }

        let staticText = element.staticTexts.firstMatch
        if staticText.exists {
            return staticText.label
        }

        return element.value as? String ?? ""
    }

    @MainActor
    private func attachDebugHierarchy(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
