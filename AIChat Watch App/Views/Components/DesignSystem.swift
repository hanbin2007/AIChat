//
//  DesignSystem.swift
//  AIChat Watch App
//
//  Centralised tokens for spacing, radii, status colors, and typography.
//  Keeps the visual layer aligned with watchOS 26 system materials —
//  no custom palette beyond accent + status semantics.
//

import SwiftUI

enum DS {
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Radius {
        static let bubble: CGFloat = 14
        static let card: CGFloat = 12
        static let chip: CGFloat = 8
    }

    enum Status {
        static let ok = Color.green
        static let warn = Color.yellow
        static let danger = Color.red
        static let info = Color.accentColor
    }

    enum Typography {
        static let bubbleBody = Font.body
        static let bubbleMeta = Font.caption2
        static let listTitle = Font.headline
        static let listPreview = Font.footnote
        static let chip = Font.caption2.weight(.medium)
        static let sectionHeader = Font.caption.weight(.semibold)
    }
}

extension View {
    /// Card-style container — thin material bg + rounded corners.
    /// Used for Home sections, ActivationStatusCard, etc.
    func dsCard(padding: CGFloat = DS.Spacing.m) -> some View {
        self
            .padding(padding)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
