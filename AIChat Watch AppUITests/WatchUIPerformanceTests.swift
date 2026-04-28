//
//  WatchUIPerformanceTests.swift
//  AIChat Watch AppUITests
//
//  Watch UI performance and hang-monitor tests. Skipped by default — see
//  `UIPerformanceTestCase` for the rationale and how to enable.
//
//  Each `measure(metrics:)` call records its own per-machine baseline.
//  Hang-monitor assertions still gate to "0 hang events" because that's
//  the regression we care about, but they only run inside this perf
//  suite and don't block the regular UI test run.
//

import XCTest

final class WatchUIPerformanceTests: UIPerformanceTestCase {

    @MainActor
    func testConversationListScrollPerformance() throws {
        let app = XCUIApplication()
        measure(metrics: conversationListScrollMetrics(for: app)) {
            app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_list_scroll_performance"
            app.launch()

            let list = app.collectionViews["conversation.list"].firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 10))

            for _ in 0..<4 {
                list.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
                list.swipeDown()
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            }

            app.terminate()
        }
    }

    @MainActor
    func testHeavyMarkdownConversationRendersWithoutBlockingInitialLoad() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_heavy_markdown"
        app.launchEnvironment["AIChat_UI_TEST_ENABLE_HANG_MONITOR"] = "1"
        app.launch()

        let scrollView = app.scrollViews["conversation.messages.scroll"]
        if !scrollView.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Missing heavy-markdown conversation hierarchy")
            XCTFail("Missing conversation scroll view for heavy markdown.")
            return
        }

        attachScreenshot(app, named: "heavy-markdown-loading")

        let heading = app.staticTexts["推导步骤"].firstMatch
        if !heading.waitForExistence(timeout: 10) {
            attachDebugHierarchy(app, named: "Heavy markdown heading missing hierarchy")
            attachScreenshot(app, named: "heavy-markdown-load-failure")
            XCTFail("The heavy markdown reply did not finish its initial render.")
            return
        }

        assertZeroDetectedHangs(in: app, context: "heavy-markdown-initial-load")
        attachScreenshot(app, named: "heavy-markdown-loaded")
    }

    @MainActor
    func testHeavyMarkdownInitialRenderPerformance() throws {
        let app = XCUIApplication()
        measure(metrics: heavyMarkdownInitialRenderMetrics(for: app)) {
            app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_heavy_markdown"
            app.launch()

            let heading = app.staticTexts["推导步骤"].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor
    func testStreamingScrollPerformanceWithHangMonitor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_streaming_scroll_performance"
        app.launchEnvironment["AIChat_UI_TEST_ENABLE_HANG_MONITOR"] = "1"
        app.launch()

        let scrollView = app.scrollViews["conversation.messages.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Missing conversation scroll view.")

        // Wait for streaming to begin (the streaming service fires after 2s).
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        // Scroll up and down four rounds while streaming is active.
        for _ in 1...4 {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            app.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        // Wait for streaming to finish (30 chunks × 80ms = ~2.4s, plus margin).
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        assertZeroDetectedHangs(in: app, context: "streaming-scroll-performance")
        attachScreenshot(app, named: "streaming-scroll-performance-finish")
    }

    @MainActor
    func testStreamingScrollPerformanceMeasure() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_streaming_scroll_performance"
        app.launch()

        let scrollView = app.scrollViews["conversation.messages.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Missing conversation scroll view.")

        // Wait for streaming to begin.
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        let metrics = conversationListScrollMetrics(for: app)

        measure(metrics: metrics) {
            for _ in 1...4 {
                app.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                app.swipeDown()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }
    }

    /// High-pressure streaming: ~66 tokens/s × 6s + long thought summary +
    /// aggressive scroll loop, watchOS hang monitor enabled. If the pacer
    /// or the 1 Hz checkpoint path regresses to touch `@Published
    /// conversations` per-token again, the hang monitor trips here first.
    @MainActor
    func testStreamingStressWithHangMonitor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["AIChat_UI_TEST_SCENARIO"] = "conversation_streaming_stress"
        app.launchEnvironment["AIChat_UI_TEST_ENABLE_HANG_MONITOR"] = "1"
        app.launch()

        let scrollView = app.scrollViews["conversation.messages.scroll"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Missing conversation scroll view.")

        // Let the stream start (service fires after 2s bootstrap delay,
        // plus a short amount of thought summary before the answer flood).
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        // Eight rounds of back-to-back swipes with NO settle pause between
        // opposite swipes. The previous perf test inserts 0.3s between
        // each swipe — this one deliberately doesn't, to stress the
        // scroll-gesture suppression machinery.
        for _ in 1...8 {
            app.swipeUp()
            app.swipeDown()
        }

        // Wait for the full answer flood (400 chunks × 15ms ≈ 6s plus margin).
        RunLoop.current.run(until: Date().addingTimeInterval(8))

        assertZeroDetectedHangs(in: app, context: "streaming-stress")
        attachScreenshot(app, named: "streaming-stress-finish")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Helpers

    @MainActor
    private func conversationListScrollMetrics(for app: XCUIApplication) -> [any XCTMetric] {
        if #available(watchOS 26.0, *) {
            return [
                XCTClockMetric(),
                XCTHitchMetric(application: app),
                XCTOSSignpostMetric.scrollingAndDecelerationMetric
            ]
        }

        return [
            XCTClockMetric(),
            XCTOSSignpostMetric.scrollingAndDecelerationMetric
        ]
    }

    @MainActor
    private func heavyMarkdownInitialRenderMetrics(for app: XCUIApplication) -> [any XCTMetric] {
        if #available(watchOS 26.0, *) {
            return [XCTClockMetric(), XCTHitchMetric(application: app)]
        }

        return [XCTClockMetric()]
    }

    @MainActor
    private func assertZeroDetectedHangs(in app: XCUIApplication, context: String) {
        let telemetry = app.staticTexts["ui-test-hang-monitor"].firstMatch
        XCTAssertTrue(telemetry.waitForExistence(timeout: 10), "Missing hang monitor telemetry for \(context).")

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let values = parseDebugTelemetry(from: telemetry.label)
        let count = Int(values["count"] ?? "")
        let maxMilliseconds = values["maxMs"] ?? "missing"

        let evidence = XCTAttachment(
            string: [
                "context=\(context)",
                "label=\(telemetry.label)",
                "count=\(count.map(String.init) ?? "missing")",
                "maxMs=\(maxMilliseconds)"
            ].joined(separator: "\n")
        )
        evidence.name = "\(context)-hang-monitor"
        evidence.lifetime = .keepAlways
        add(evidence)

        XCTAssertEqual(count, 0, "Detected non-zero hang events for \(context). maxMs=\(maxMilliseconds)")
    }

    private func parseDebugTelemetry(from label: String) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: label
                .split(separator: ";")
                .compactMap { item in
                    let parts = item.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else {
                        return nil
                    }
                    return (String(parts[0]), String(parts[1]))
                }
        )
    }
}
