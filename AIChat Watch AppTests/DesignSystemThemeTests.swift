//
//  DesignSystemThemeTests.swift
//  AIChat Watch AppTests
//
//  Guards against regressions where the app backdrop follows Light Mode while
//  shared cards and message text keep hard-coded dark-mode colors.
//

import XCTest
@testable import AIChat_Watch_App

final class DesignSystemThemeTests: XCTestCase {
    func testLightModePaletteUsesDarkTextAndLightSurfaces() async throws {
        let palette = DS.Theme.palette(for: .light)

        XCTAssertLessThan(palette.primaryText.luminance, 0.35)
        XCTAssertGreaterThan(palette.elevatedSurface.luminance, 0.75)
        XCTAssertLessThan(palette.elevatedSurface.alpha, 0.92)
        XCTAssertGreaterThan(palette.elevatedStroke.luminance, 0.20)
    }

    func testDarkModePaletteKeepsLightTextAndDarkSurfaces() async throws {
        let palette = DS.Theme.palette(for: .dark)

        XCTAssertGreaterThan(palette.primaryText.luminance, 0.75)
        XCTAssertLessThan(palette.elevatedSurface.luminance, 0.20)
        XCTAssertLessThan(palette.elevatedSurface.alpha, 0.72)
        XCTAssertGreaterThan(palette.elevatedStroke.luminance, 0.75)
    }
}
