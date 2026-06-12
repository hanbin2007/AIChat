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

nonisolated enum DS {

    // MARK: - Theme

    nonisolated enum Theme {
        nonisolated enum Scheme {
            case light
            case dark

            init(_ colorScheme: ColorScheme) {
                self = colorScheme == .dark ? .dark : .light
            }
        }

        nonisolated struct RGBA: Equatable {
            let red: Double
            let green: Double
            let blue: Double
            let alpha: Double

            var color: Color {
                Color(red: red, green: green, blue: blue).opacity(alpha)
            }

            var luminance: Double {
                (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            }
        }

        nonisolated struct Palette: Equatable {
            let primaryText: RGBA
            let secondaryText: RGBA
            let tertiaryText: RGBA
            let mutedText: RGBA
            let elevatedSurface: RGBA
            let elevatedSurfaceStrong: RGBA
            let elevatedStroke: RGBA
            let subtleFill: RGBA
            let subtleStroke: RGBA
            let assistantSurfaceTop: RGBA
            let assistantSurfaceBottom: RGBA
            let assistantStroke: RGBA
            let liveHighlight: RGBA
            let pausedHighlight: RGBA
            let trackSurfaceLeading: RGBA
            let trackSurfaceMiddle: RGBA
            let trackSurfaceTrailing: RGBA
        }

        static func palette(for scheme: Scheme) -> Palette {
            switch scheme {
            case .dark:
                return Palette(
                    primaryText: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 1.00),
                    secondaryText: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.68),
                    tertiaryText: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.52),
                    mutedText: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.80),
                    elevatedSurface: RGBA(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.40),
                    elevatedSurfaceStrong: RGBA(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.50),
                    elevatedStroke: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.08),
                    subtleFill: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.07),
                    subtleStroke: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.08),
                    assistantSurfaceTop: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.08),
                    assistantSurfaceBottom: RGBA(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.46),
                    assistantStroke: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.09),
                    liveHighlight: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.95),
                    pausedHighlight: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.82),
                    trackSurfaceLeading: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.05),
                    trackSurfaceMiddle: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.10),
                    trackSurfaceTrailing: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.06)
                )
            case .light:
                return Palette(
                    primaryText: RGBA(red: 0.06, green: 0.11, blue: 0.15, alpha: 1.00),
                    secondaryText: RGBA(red: 0.10, green: 0.18, blue: 0.24, alpha: 0.74),
                    tertiaryText: RGBA(red: 0.13, green: 0.22, blue: 0.30, alpha: 0.58),
                    mutedText: RGBA(red: 0.10, green: 0.18, blue: 0.24, alpha: 0.80),
                    elevatedSurface: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.72),
                    elevatedSurfaceStrong: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.86),
                    elevatedStroke: RGBA(red: 0.12, green: 0.24, blue: 0.32, alpha: 0.14),
                    subtleFill: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.56),
                    subtleStroke: RGBA(red: 0.12, green: 0.24, blue: 0.32, alpha: 0.12),
                    assistantSurfaceTop: RGBA(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.82),
                    assistantSurfaceBottom: RGBA(red: 0.86, green: 0.94, blue: 0.98, alpha: 0.76),
                    assistantStroke: RGBA(red: 0.12, green: 0.24, blue: 0.32, alpha: 0.14),
                    liveHighlight: RGBA(red: 0.86, green: 0.98, blue: 1.00, alpha: 0.92),
                    pausedHighlight: RGBA(red: 0.18, green: 0.25, blue: 0.30, alpha: 0.46),
                    trackSurfaceLeading: RGBA(red: 0.20, green: 0.34, blue: 0.42, alpha: 0.08),
                    trackSurfaceMiddle: RGBA(red: 0.20, green: 0.34, blue: 0.42, alpha: 0.14),
                    trackSurfaceTrailing: RGBA(red: 0.20, green: 0.34, blue: 0.42, alpha: 0.10)
                )
            }
        }

        static func palette(for colorScheme: ColorScheme) -> Palette {
            palette(for: Scheme(colorScheme))
        }
    }

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
        static func assistantFill(for colorScheme: ColorScheme) -> LinearGradient {
            let palette = Theme.palette(for: colorScheme)
            return LinearGradient(
                colors: [
                    palette.assistantSurfaceTop.color,
                    palette.assistantSurfaceBottom.color
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static let userStroke = Color.white.opacity(0.20)
        static func assistantStroke(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).assistantStroke.color
        }
    }

    // MARK: - Text foreground

    enum Text {
        static func primary(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).primaryText.color
        }

        static func secondary(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).secondaryText.color
        }

        static func tertiary(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).tertiaryText.color
        }

        static func muted(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).mutedText.color
        }
    }

    // MARK: - Status accents

    enum Status {
        static let live = Color.cyan.opacity(0.92)
        static let paused = Color.gray.opacity(0.88)
        static let failure = Color.yellow

        static func liveHighlight(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).liveHighlight.color
        }

        static func pausedHighlight(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).pausedHighlight.color
        }
    }

    // MARK: - Surfaces

    enum Surface {
        static func elevatedFill(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).elevatedSurface.color
        }

        static func elevatedStrongFill(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).elevatedSurfaceStrong.color
        }

        static func elevatedStroke(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).elevatedStroke.color
        }

        static func subtleFill(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).subtleFill.color
        }

        static func subtleStroke(for colorScheme: ColorScheme) -> Color {
            Theme.palette(for: colorScheme).subtleStroke.color
        }

        static func trackGradientColors(for colorScheme: ColorScheme) -> [Color] {
            let palette = Theme.palette(for: colorScheme)
            return [
                palette.trackSurfaceLeading.color,
                palette.trackSurfaceMiddle.color,
                palette.trackSurfaceTrailing.color
            ]
        }
    }
}
