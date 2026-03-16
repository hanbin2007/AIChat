//
//  AIChat_Watch_AppUITests.swift
//  AIChat Watch AppUITests
//
//  Created by zhb on 2026/3/7.
//

import CoreGraphics
import Foundation
import XCTest

final class AIChat_Watch_AppUITests: XCTestCase {
    private enum ScrollDirection {
        case up
        case down
    }

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
        if !revealElement(displayFormula, in: app, directions: [.up], timeout: 10) {
            attachDebugHierarchy(app, named: "Missing block math trigger hierarchy")
            XCTFail("Missing block math trigger.")
            return
        }
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
    }

    @MainActor
    func testLastFormulaRendersAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "formula_zoom"
        app.launch()

        let harness = app.descendants(matching: .any)["formula.zoom.harness"]
        XCTAssertTrue(harness.waitForExistence(timeout: 10))

        let fullContent = app.descendants(matching: .any)["formula.zoom.full_content.container"]
        XCTAssertTrue(revealElement(fullContent, in: app, directions: [.up], timeout: 10))

        let targetContainer = app.descendants(matching: .any)["formula.zoom.last_formula.container"]
        if !revealElement(targetContainer, in: app, directions: [.down, .up], timeout: 10) {
            attachDebugHierarchy(app, named: "Missing last formula container hierarchy")
            XCTFail("Missing deterministic target for the last formula.")
            return
        }

        let invalidFormula = targetContainer.descendants(matching: .any)["math.invalid.inline"]
        if invalidFormula.exists {
            attachScreenshot(app, named: "last-formula-invalid")
            XCTFail("The last formula rendered as an invalid math view.")
            return
        }

        XCTAssertFalse(targetContainer.staticTexts["Formula format issue"].exists)
        XCTAssertFalse(targetContainer.staticTexts["Formula unsupported"].exists)

        attachScreenshot(app, named: "last-formula-card")

        let inlineFormulaQuery = targetContainer
            .descendants(matching: .any)
            .matching(identifier: "math.zoom.trigger.inline")
        XCTAssertEqual(inlineFormulaQuery.count, 1)

        let targetFormula = inlineFormulaQuery.firstMatch
        if !revealElement(targetFormula, in: app, directions: [.down, .up], timeout: 10) {
            attachDebugHierarchy(app, named: "Missing last formula trigger hierarchy")
            XCTFail("Missing tappable inline math trigger for the last formula.")
            return
        }

        targetFormula.tap()

        let zoomSheet = app.descendants(matching: .any)["math.zoom.sheet"]
        if !zoomSheet.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing zoom sheet for last formula hierarchy")
            XCTFail("Missing zoom sheet for the last formula.")
            return
        }

        XCTAssertTrue(app.buttons["math.zoom.close"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "last-formula-zoomed")
    }

    @MainActor
    func testConversationToolEntryOpensSheetAndAllowsDismissalAfterInteractingWithControls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "tool_entry"
        app.launch()

        let toolEntry = app.descendants(matching: .any)["conversation.tool-entry"]
        if !toolEntry.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing tool entry hierarchy")
            XCTFail("Missing tool entry button in the watch composer.")
            return
        }

        XCTAssertEqual(toolEntry.label, "工具与图片")
        XCTAssertTrue(waitForHittable(toolEntry, timeout: 5))
        toolEntry.tap()

        let toolSheet = app.descendants(matching: .any)["conversation.tool-sheet"]
        if !toolSheet.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing tool sheet hierarchy")
            XCTFail("Missing tool sheet after tapping the tool entry.")
            return
        }

        let searchSwitch = app.switches["conversation.tool-search"].firstMatch
        if !searchSwitch.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing search toggle hierarchy")
            XCTFail("Missing Google Search toggle in the tool sheet.")
            return
        }

        let codeSwitch = app.switches["conversation.tool-code"].firstMatch
        if !codeSwitch.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Missing code toggle hierarchy")
            XCTFail("Missing Code Execution toggle in the tool sheet.")
            return
        }

        let photoEntry = app.descendants(matching: .any)["conversation.tool-photo-picker"]
        XCTAssertTrue(photoEntry.waitForExistence(timeout: 5))

        searchSwitch.tap()
        codeSwitch.tap()

        let doneButton = app.buttons["conversation.tool-done"]
        if !revealElement(doneButton, in: app, directions: [.up], timeout: 5) {
            attachDebugHierarchy(app, named: "Missing tool done button hierarchy")
            XCTFail("Missing done button in the tool sheet.")
            return
        }
        doneButton.tap()

        XCTAssertFalse(toolSheet.waitForExistence(timeout: 2))
        XCTAssertTrue(toolEntry.waitForExistence(timeout: 5))
    }

    @MainActor
    func testConversationRowOpensDetailView() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_navigation"
        app.launch()

        let row = app.descendants(matching: .any)["conversation.row.00000000-0000-0000-0000-000000000201"]
        if !revealConversationRowIfNeeded(row, in: app) {
            attachDebugHierarchy(app, named: "Missing conversation row hierarchy")
            XCTFail("Missing conversation row in the watch list.")
            return
        }
        row.tap()

        let toolEntry = app.descendants(matching: .any)["conversation.tool-entry"]
        if !toolEntry.waitForExistence(timeout: 5) {
            attachDebugHierarchy(app, named: "Conversation detail did not open hierarchy")
            XCTFail("Conversation detail did not open after tapping the row.")
            return
        }

        XCTAssertTrue(toolEntry.isHittable)
    }

    @MainActor
    func testDeletingConversationPersistsAcrossRelaunch() throws {
        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatUITests-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuiteName = "AIChatUITests.DeletePersistence.\(UUID().uuidString)"
        let conversationID = "00000000-0000-0000-0000-000000000301"
        let rowIdentifier = "conversation.row.\(conversationID)"
        let deleteIdentifier = "conversation.delete.\(conversationID)"
        let app = XCUIApplication()

        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_delete_persistence"
        app.launchEnvironment["AIChat_UI_TEST_STORAGE_ROOT"] = storageRoot.path
        app.launchEnvironment["AIChat_UI_TEST_DEFAULTS_SUITE"] = defaultsSuiteName
        app.launchEnvironment["AIChat_UI_TEST_DELETE_RESET"] = "1"
        app.launch()

        let row = app.descendants(matching: .any)[rowIdentifier]
        if !revealElement(row, in: app, directions: [.up], timeout: 10) {
            attachDebugHierarchy(app, named: "Missing seeded delete-persistence row hierarchy")
            XCTFail("Missing seeded conversation row for delete persistence test.")
            return
        }
        row.swipeLeft()

        let deleteButton = app.buttons[deleteIdentifier]
        if !revealElement(deleteButton, in: app, directions: [.up], timeout: 5) {
            attachDebugHierarchy(app, named: "Missing delete action hierarchy")
            XCTFail("Missing delete swipe action for the seeded conversation.")
            return
        }
        deleteButton.tap()

        XCTAssertFalse(row.waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment["AIChat_UI_TEST_DELETE_RESET"] = "0"
        app.launch()

        let relaunchedRow = app.descendants(matching: .any)[rowIdentifier]
        XCTAssertFalse(relaunchedRow.waitForExistence(timeout: 5))
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
    private func revealConversationRowIfNeeded(
        _ row: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        if revealElement(row, in: app, directions: [.up], timeout: 10) {
            return true
        }

        let horizontalSwipes: [(XCUIApplication) -> Void] = [
            { $0.swipeLeft() },
            { $0.swipeRight() },
            { $0.swipeLeft() }
        ]

        for horizontalSwipe in horizontalSwipes {
            horizontalSwipe(app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))

            if revealElement(row, in: app, directions: [.up], timeout: 4) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func revealElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        directions: [ScrollDirection],
        timeout: TimeInterval,
        maxSwipesPerDirection: Int = 6
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && waitForHittable(element, timeout: 0.2) {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        for direction in directions {
            for _ in 0..<maxSwipesPerDirection {
                performScroll(direction, in: app)
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))

                if element.exists && waitForHittable(element, timeout: 0.5) {
                    return true
                }
            }
        }

        return element.exists && element.isHittable
    }

    @MainActor
    private func performScroll(
        _ direction: ScrollDirection,
        in app: XCUIApplication
    ) {
        switch direction {
        case .up:
            app.swipeUp()
        case .down:
            app.swipeDown()
        }
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

    @MainActor
    @discardableResult
    private func attachScreenshot(_ app: XCUIApplication, named name: String) -> URL? {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileURL = screenshotArtifactsDirectory().appendingPathComponent("\(name).png")
        do {
            try screenshot.pngRepresentation.write(to: fileURL)
            let pathAttachment = XCTAttachment(string: fileURL.path)
            pathAttachment.name = "\(name)-path"
            pathAttachment.lifetime = .keepAlways
            add(pathAttachment)
            return fileURL
        } catch {
            let errorAttachment = XCTAttachment(string: "Failed to persist screenshot \(name): \(error)")
            errorAttachment.name = "\(name)-write-error"
            errorAttachment.lifetime = .keepAlways
            add(errorAttachment)
            return nil
        }
    }

    private func screenshotArtifactsDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatUITestArtifacts", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
