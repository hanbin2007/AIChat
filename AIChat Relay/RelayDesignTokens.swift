//
//  RelayDesignTokens.swift
//  AIChat Relay
//
//  Shared design-system views and color tokens used across all Relay pages.
//  Extracted from RelayDashboardView to enable reuse by page-level views.
//

import SwiftUI

// MARK: - Surface styles

enum RelaySurfaceStyle {
    case panel
    case card
    case field
    case pill
    case toast
}

// MARK: - Panel / card containers

struct RelayPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(relaySurfaceFill(colorScheme, style: .panel))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(relaySurfaceStroke(colorScheme, style: .panel), lineWidth: 1.1)
                    )
                    .shadow(color: relayShadowColor(colorScheme), radius: 20, x: 0, y: 14)
            )
    }
}

struct RelayMetricTile<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let accent: Color
    let content: Content

    init(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 10, height: 10)

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(relaySurfaceStroke(colorScheme, style: .card), lineWidth: 1)
                )
        )
    }
}

// MARK: - Pills & badges

struct RelayPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .pill))
        )
    }
}

// MARK: - Inline message

struct RelayInlineMessage: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text(message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

// MARK: - Setup step row

struct RelaySetupStepRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let step: RelaySetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(stepTint.opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: stepSymbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(stepTint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))

                    Text(stepStatusText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(stepTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(stepTint.opacity(0.12))
                        )
                }

                Text(step.detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }

    private var stepTint: Color {
        switch step.status {
        case .complete: return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .pending:  return Color.orange
        case .blocked:  return Color.red
        }
    }

    private var stepSymbol: String {
        switch step.status {
        case .complete: return "checkmark"
        case .pending:  return "ellipsis"
        case .blocked:  return "exclamationmark"
        }
    }

    private var stepStatusText: String {
        switch step.status {
        case .complete: return "Ready"
        case .pending:  return "Pending"
        case .blocked:  return "Blocked"
        }
    }
}

// MARK: - Endpoint row

struct RelayEndpointRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let endpoint: RelayEndpoint
    let copyAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: endpoint.title == "LAN" ? "wifi" : "desktopcomputer")
                        .foregroundStyle(endpoint.title == "LAN" ? Color(red: 0.72, green: 0.43, blue: 0.19) : Color(red: 0.08, green: 0.38, blue: 0.44))

                    Text(endpoint.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Text(endpoint.urlString)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(endpoint.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Copy URL") {
                copyAction()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

// MARK: - Field group / toggle tile

struct RelayFieldGroup<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    let validation: String
    let validationTint: Color
    let content: Content

    init(
        title: String,
        detail: String,
        validation: String,
        validationTint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.validation = validation
        self.validationTint = validationTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(relaySurfaceFill(colorScheme, style: .field))
            )

            Text(validation)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(validationTint)
        }
    }
}

struct RelayToggleTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .field))
        )
    }
}

// MARK: - Search field

struct RelaySearchField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .field))
        )
    }
}

// MARK: - Empty state

struct RelayEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .card))
        )
    }
}

// MARK: - Feedback toast

struct RelayFeedbackToast: View {
    @Environment(\.colorScheme) private var colorScheme
    let feedback: RelayActionFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(feedback.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(relaySurfaceFill(colorScheme, style: .toast))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(tint.opacity(0.22), lineWidth: 1.2)
                )
                .shadow(color: relayShadowColor(colorScheme, elevated: true), radius: 20, x: 0, y: 12)
        )
    }

    private var tint: Color {
        switch feedback.style {
        case .info:    return Color.blue
        case .success: return Color(red: 0.16, green: 0.47, blue: 0.29)
        case .warning: return Color.orange
        case .error:   return Color.red
        }
    }

    private var iconName: String {
        switch feedback.style {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
}

// MARK: - Wrap layout

struct WrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > maxWidth, cursorX > 0 {
                maxLineWidth = max(maxLineWidth, cursorX - spacing)
                cursorX = 0
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        maxLineWidth = max(maxLineWidth, cursorX - spacing)
        return CGSize(width: max(0, maxLineWidth), height: cursorY + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursorX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Color / style tokens

func relayCanvasGradient(_ colorScheme: ColorScheme) -> [Color] {
    switch colorScheme {
    case .dark:
        return [
            Color(red: 0.07, green: 0.09, blue: 0.12),
            Color(red: 0.12, green: 0.10, blue: 0.09),
        ]
    case .light:
        return [
            Color(red: 0.95, green: 0.97, blue: 0.98),
            Color(red: 0.98, green: 0.95, blue: 0.91),
        ]
    @unknown default:
        return [
            Color(red: 0.95, green: 0.97, blue: 0.98),
            Color(red: 0.98, green: 0.95, blue: 0.91),
        ]
    }
}

func relayCanvasAccent(_ colorScheme: ColorScheme, warm: Bool) -> Color {
    switch colorScheme {
    case .dark:
        return warm
            ? Color(red: 0.67, green: 0.42, blue: 0.21).opacity(0.16)
            : Color(red: 0.19, green: 0.42, blue: 0.52).opacity(0.22)
    case .light:
        return warm
            ? Color(red: 0.87, green: 0.58, blue: 0.29).opacity(0.18)
            : Color(red: 0.27, green: 0.54, blue: 0.64).opacity(0.17)
    @unknown default:
        return warm
            ? Color(red: 0.87, green: 0.58, blue: 0.29).opacity(0.18)
            : Color(red: 0.27, green: 0.54, blue: 0.64).opacity(0.17)
    }
}

func relaySurfaceFill(_ colorScheme: ColorScheme, style: RelaySurfaceStyle) -> Color {
    switch colorScheme {
    case .dark:
        switch style {
        case .panel: return Color.white.opacity(0.08)
        case .card:  return Color.white.opacity(0.06)
        case .field: return Color.white.opacity(0.10)
        case .pill:  return Color.white.opacity(0.12)
        case .toast: return Color(red: 0.11, green: 0.12, blue: 0.15).opacity(0.96)
        }
    case .light:
        switch style {
        case .panel: return Color.white.opacity(0.64)
        case .card:  return Color.white.opacity(0.58)
        case .field: return Color.white.opacity(0.72)
        case .pill:  return Color.white.opacity(0.86)
        case .toast: return Color.white.opacity(0.94)
        }
    @unknown default:
        return style == .toast ? Color.white.opacity(0.94) : Color.white.opacity(0.64)
    }
}

func relaySurfaceStroke(_ colorScheme: ColorScheme, style: RelaySurfaceStyle) -> Color {
    switch colorScheme {
    case .dark:
        switch style {
        case .panel: return Color.white.opacity(0.12)
        case .card:  return Color.white.opacity(0.10)
        case .field: return Color.white.opacity(0.12)
        case .pill:  return Color.white.opacity(0.14)
        case .toast: return Color.white.opacity(0.12)
        }
    case .light:
        switch style {
        case .panel: return Color.white.opacity(0.72)
        case .card:  return Color.white.opacity(0.55)
        case .field: return Color.white.opacity(0.68)
        case .pill:  return Color.white.opacity(0.82)
        case .toast: return Color.white.opacity(0.82)
        }
    @unknown default:
        return Color.white.opacity(0.55)
    }
}

func relayShadowColor(_ colorScheme: ColorScheme, elevated: Bool = false) -> Color {
    switch colorScheme {
    case .dark:
        return Color.black.opacity(elevated ? 0.34 : 0.28)
    case .light:
        return Color.black.opacity(elevated ? 0.12 : 0.08)
    @unknown default:
        return Color.black.opacity(0.08)
    }
}

func relayDividerColor(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:    return Color.white.opacity(0.12)
    case .light:   return Color.white.opacity(0.45)
    @unknown default: return Color.white.opacity(0.45)
    }
}

func relayEditorBackground(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:    return Color.black.opacity(0.66)
    case .light:   return Color.black.opacity(0.90)
    @unknown default: return Color.black.opacity(0.90)
    }
}

func relayEditorForeground(_ colorScheme: ColorScheme) -> Color {
    switch colorScheme {
    case .dark:    return Color(red: 0.75, green: 0.95, blue: 0.80)
    case .light:   return Color(red: 0.62, green: 0.94, blue: 0.74)
    @unknown default: return Color(red: 0.62, green: 0.94, blue: 0.74)
    }
}
