//
//  UITestSupport.swift
//  AIChat iOS AppUITests
//
//  Shared XCUIApplication helpers used across iOS UI test classes:
//  hittability polling, screenshot/hierarchy attachment.
//

import Foundation
import XCTest

extension XCTestCase {
    /// Poll `element.isHittable` up to `timeout` using a 0.1s `RunLoop` step.
    @MainActor
    func waitForHittable(
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

    /// Attach the application's accessibility hierarchy as a debugging artifact.
    @MainActor
    func attachDebugHierarchy(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Capture a screenshot, attach it to the test record, and persist a PNG copy
    /// to `screenshotArtifactsDirectory(for:)`. The persisted path is also attached
    /// so CI scripts can locate the file. Returns the persisted file URL on success.
    @MainActor
    @discardableResult
    func attachScreenshot(_ app: XCUIApplication, named name: String) -> URL? {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let fileURL = screenshotArtifactsDirectory(for: app)
            .appendingPathComponent("\(name).png")
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

    /// The directory where attachScreenshot persists PNGs. Resolution order:
    /// 1. `AIChat_UI_TEST_ARTIFACTS_ROOT` from the host process environment
    /// 2. Same key from the launched app's `launchEnvironment`
    /// 3. `<temp>/AIChatUITestArtifacts`
    @MainActor
    func screenshotArtifactsDirectory(for app: XCUIApplication) -> URL {
        let directory: URL
        if let configuredRoot = ProcessInfo.processInfo.environment["AIChat_UI_TEST_ARTIFACTS_ROOT"],
           configuredRoot.isEmpty == false {
            directory = URL(fileURLWithPath: configuredRoot, isDirectory: true)
        } else if let configuredRoot = app.launchEnvironment["AIChat_UI_TEST_ARTIFACTS_ROOT"],
           configuredRoot.isEmpty == false {
            directory = URL(fileURLWithPath: configuredRoot, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatUITestArtifacts", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
