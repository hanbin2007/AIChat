//
//  CompanionSelectionReconciler.swift
//  Shared Licensing
//
//  Pure logic for choosing the next selected conversation after the
//  conversation list changes (deletion / sync replacement / etc.).
//
//  Lives in Shared Licensing so the iOS Companion's
//  `NavigationSplitView` selection rule can be unit-tested from the
//  watchOS test target without spinning up SwiftUI. The function is
//  iOS-flavored (split view popping behavior), but the *decision* is
//  platform-agnostic — it takes a plain `Bool` for compact-vs-regular.
//

import Foundation

enum CompanionSelectionReconciler {
    /// Returns the conversation ID that should be selected after the list
    /// of available conversation IDs changes.
    ///
    /// Behavior:
    /// - List empty → `nil` (no selection possible).
    /// - Current selection still in the list → keep it (no churn).
    /// - Current selection gone (typically: user deleted the open one)
    ///   - on iPhone (`isCompactSizeClass == true`) → `nil` so the
    ///     `NavigationSplitView` pops back to the list. Avoids the
    ///     surprise "auto-jumped into another conversation" behavior
    ///     reported in issue #32.
    ///   - on iPad (`isCompactSizeClass == false`) → first available ID
    ///     so the detail column in the two-column layout stays populated.
    static func reconcile(
        currentSelection: UUID?,
        availableIDs: [UUID],
        isCompactSizeClass: Bool
    ) -> UUID? {
        guard availableIDs.isEmpty == false else {
            return nil
        }

        if let currentSelection, availableIDs.contains(currentSelection) {
            return currentSelection
        }

        if isCompactSizeClass {
            return nil
        }
        return availableIDs.first
    }
}
