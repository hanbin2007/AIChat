//
//  OverflowScrollingText.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/9.
//

import SwiftUI

struct OverflowScrollingText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary
    var gap: CGFloat = 20
    var speed: CGFloat = 28
    var expandsHorizontally: Bool = false

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var shouldScroll: Bool {
        containerWidth > 0 && textWidth > containerWidth + 1
    }

    var body: some View {
        widthBehavior {
            Group {
                if shouldScroll {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let cycleDistance = textWidth + gap
                        let cycleDuration = max(Double(cycleDistance / max(speed, 1)), 0.1)
                        let elapsed = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycleDuration)
                        let progress = elapsed / cycleDuration
                        let offset = -CGFloat(progress) * cycleDistance

                        HStack(spacing: gap) {
                            textView(fixed: true)
                            textView(fixed: true)
                        }
                        .offset(x: offset)
                    }
                } else {
                    textView(fixed: false)
                }
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: OverflowScrollingTextContainerWidthPreferenceKey.self,
                    value: geometry.size.width
                )
            }
        )
        .overlay(alignment: .leading) {
            textView(fixed: true)
                .hidden()
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: OverflowScrollingTextWidthPreferenceKey.self,
                            value: geometry.size.width
                        )
                    }
                )
                .allowsHitTesting(false)
        }
        .onPreferenceChange(OverflowScrollingTextWidthPreferenceKey.self) { textWidth = $0 }
        .onPreferenceChange(OverflowScrollingTextContainerWidthPreferenceKey.self) { containerWidth = $0 }
        .clipped()
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private func textView(fixed: Bool) -> some View {
        let view = Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)

        if fixed {
            view.fixedSize(horizontal: true, vertical: false)
        } else {
            view
        }
    }

    @ViewBuilder
    private func widthBehavior<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if expandsHorizontally {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
        }
    }
}

private struct OverflowScrollingTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct OverflowScrollingTextContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
