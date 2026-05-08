//
//  AODPrivacyModifier.swift
//  AIChat Watch App
//
//  Watch always-on-display privacy guard. When the screen is luminance-
//  reduced (wrist down, AOD active), the modifier:
//    • redacts the wrapped view
//    • reports the state to `WatchDisplayStateMonitor` so background
//      services can react if they need to
//
//  Apply at the top of any view that renders sensitive conversation
//  content — primarily `ConversationDetailView` and bubble-rendering
//  components.
//

import SwiftUI

struct AODPrivacyModifier: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content
            .redacted(reason: isLuminanceReduced ? .privacy : [])
            .onChange(of: isLuminanceReduced, initial: true) { _, newValue in
                WatchDisplayStateMonitor.shared.updateLuminanceReduced(newValue)
            }
    }
}

extension View {
    /// Hides sensitive content on the always-on display.
    func aodPrivacy() -> some View {
        modifier(AODPrivacyModifier())
    }
}
