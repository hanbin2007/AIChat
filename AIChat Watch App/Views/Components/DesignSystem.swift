//
//  DesignSystem.swift
//  AIChat Watch App
//
//  Centralized visual tokens for the conversation surface. Previously
//  every opacity/radius/gradient was an inline magic number scattered
//  across ChatBubbleView, ConversationDetailView, and friends — which
//  made coherent refinements impossible.
//
//  Scope is deliberate: tokens used by the chat surface, not a full
//  cross-app system. watchOS HIG bounds visual reach (small screen,
//  Always-On, no custom backdrops that fight the platform), so this
//  file concentrates on material/rhythm cues that work inside those
//  limits rather than inventing new chrome.
//

import SwiftUI

enum DS {

    // MARK: - Corner radius

    enum Radius {
        static let bubble: CGFloat = 20
        static let card: CGFloat = 14
    }

    // MARK: - Spacing

    enum Spacing {
        static let bubbleInset: CGFloat = 12
        static let bubbleContentGap: CGFloat = 8
        static let bubbleFooterGap: CGFloat = 6
    }

    // MARK: - Motion

    enum Motion {
        /// Shared motion curve — reused across auto-scroll, bubble expansion,
        /// and material transitions so the app has one cadence, not five.
        static let primaryCurve = Animation.timingCurve(0.18, 0.92, 0.22, 1.0, duration: 0.45)
        static let quickEase = Animation.easeOut(duration: 0.18)
    }

    // MARK: - Bubble materials

    enum Bubble {
        /// User bubble — brand cyan gradient, warm-to-cool diagonal.
        static let userFill = LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.70, blue: 0.88),
                Color(red: 0.00, green: 0.52, blue: 0.76)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Assistant bubble — subtle vertical glassy neutral. Avoids flat
        /// black: a faint light-to-dark gradient reads as depth on OLED
        /// without competing with text.
        static let assistantFill = LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.black.opacity(0.46)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        static let userStroke = Color.white.opacity(0.20)
        static let assistantStroke = Color.white.opacity(0.09)
    }

    // MARK: - Text foreground

    enum Text {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.68)
        static let tertiary = Color.white.opacity(0.52)
        static let muted = Color.white.opacity(0.8)
    }

    // MARK: - Status accents

    enum Status {
        static let live = Color.cyan.opacity(0.92)
        static let liveHighlight = Color.white.opacity(0.95)
        static let paused = Color.gray.opacity(0.88)
        static let pausedHighlight = Color.white.opacity(0.82)
        static let failure = Color.yellow
    }
}
