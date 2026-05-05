//
//  CompanionSelectionReconcilerTests.swift
//  AIChat Watch AppTests
//
//  Regression coverage for issue #32 — deleting the open conversation on
//  iPhone Companion was auto-jumping the user into another conversation
//  instead of popping back to the list.
//

import XCTest
@testable import AIChat_Watch_App

final class CompanionSelectionReconcilerTests: XCTestCase {

    // MARK: - Empty list

    func testEmptyListClearsSelectionRegardlessOfSizeClass() {
        let priorSelection = UUID()
        XCTAssertNil(
            CompanionSelectionReconciler.reconcile(
                currentSelection: priorSelection,
                availableIDs: [],
                isCompactSizeClass: true
            )
        )
        XCTAssertNil(
            CompanionSelectionReconciler.reconcile(
                currentSelection: priorSelection,
                availableIDs: [],
                isCompactSizeClass: false
            )
        )
    }

    // MARK: - Selection still in list (no churn)

    func testKeepsExistingSelectionWhenStillPresentCompact() {
        let alpha = UUID()
        let bravo = UUID()
        XCTAssertEqual(
            CompanionSelectionReconciler.reconcile(
                currentSelection: alpha,
                availableIDs: [alpha, bravo],
                isCompactSizeClass: true
            ),
            alpha
        )
    }

    func testKeepsExistingSelectionWhenStillPresentRegular() {
        let alpha = UUID()
        let bravo = UUID()
        XCTAssertEqual(
            CompanionSelectionReconciler.reconcile(
                currentSelection: bravo,
                availableIDs: [alpha, bravo],
                isCompactSizeClass: false
            ),
            bravo
        )
    }

    // MARK: - Issue #32 core: delete current → behavior splits by size class

    func testCompactDeletesCurrentSelectionThenPopsToList() {
        let deleted = UUID()
        let other = UUID()
        XCTAssertNil(
            CompanionSelectionReconciler.reconcile(
                currentSelection: deleted,
                availableIDs: [other],
                isCompactSizeClass: true
            ),
            "On iPhone (compact), removing the open conversation must pop back to the list, not auto-jump into another conversation."
        )
    }

    func testRegularDeletesCurrentSelectionThenAutoSelectsFirst() {
        let deleted = UUID()
        let other = UUID()
        XCTAssertEqual(
            CompanionSelectionReconciler.reconcile(
                currentSelection: deleted,
                availableIDs: [other],
                isCompactSizeClass: false
            ),
            other,
            "On iPad (regular), the detail column should stay populated to preserve the two-column layout."
        )
    }

    // MARK: - Initial / unset selection

    func testNilSelectionAutoPicksFirstOnRegularButStaysNilOnCompact() {
        let alpha = UUID()
        let bravo = UUID()

        XCTAssertEqual(
            CompanionSelectionReconciler.reconcile(
                currentSelection: nil,
                availableIDs: [alpha, bravo],
                isCompactSizeClass: false
            ),
            alpha
        )

        XCTAssertNil(
            CompanionSelectionReconciler.reconcile(
                currentSelection: nil,
                availableIDs: [alpha, bravo],
                isCompactSizeClass: true
            ),
            "Compact split view should stay on the list when nothing is selected; we never want a 'pop forward into the first row' on iPhone."
        )
    }
}
