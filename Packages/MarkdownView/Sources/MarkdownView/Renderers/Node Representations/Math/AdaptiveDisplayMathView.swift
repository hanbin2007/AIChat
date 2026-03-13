import SwiftUI
@_spi(Textual) import SwiftUIMath

struct AdaptiveDisplayMathView: View {
    let latexMath: String

    var body: some View {
        #if os(watchOS)
        WatchAdaptiveDisplayMathView(latexMath: latexMath)
        #else
        ViewThatFits(in: .horizontal) {
            Math(latexMath)
                .mathTypesettingStyle(.display)
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollView(.horizontal) {
                Math(latexMath)
                    .mathTypesettingStyle(.display)
            }
        }
        #endif
    }
}

#if os(watchOS)
private struct WatchAdaptiveDisplayMathView: View {
    private enum Layout {
        static let collapsedFont = Math.Font(name: .latinModern, size: 18)
        static let expandedFont = Math.Font(name: .latinModern, size: 24)
        static let measurementWidth: CGFloat = 10_000
    }

    let latexMath: String

    @State private var availableWidth: CGFloat = 0

    private var naturalSize: CGSize {
        measuredSize(for: Layout.collapsedFont)
    }

    private var collapsedScale: CGFloat {
        let width = max(availableWidth > 0 ? availableWidth : naturalSize.width, 1)
        guard naturalSize.width > 0 else {
            return 1
        }

        return min(1, width / naturalSize.width)
    }

    var body: some View {
        WatchZoomableMathContainer(
            latexMath: latexMath,
            expandedFont: Layout.expandedFont,
            showsIndicator: true,
            accessibilityIdentifier: "math.zoom.trigger.display"
        ) {
            ZStack(alignment: .topTrailing) {
                Math(latexMath)
                    .mathFont(Layout.collapsedFont)
                    .mathTypesettingStyle(.display)
                    .frame(width: max(naturalSize.width, 1), height: max(naturalSize.height, 1), alignment: .center)
                    .scaleEffect(collapsedScale, anchor: .center)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: max(naturalSize.height * collapsedScale, 1),
                alignment: .center
            )
            .clipped()
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: MathAvailableWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(MathAvailableWidthPreferenceKey.self) { width in
                availableWidth = width
            }
        }
    }

    private func measuredSize(for font: Math.Font) -> CGSize {
        let bounds = Math.typographicBounds(
            for: latexMath,
            fitting: ProposedViewSize(width: Layout.measurementWidth, height: nil),
            font: font,
            style: .display
        )
        let measuredSize = bounds.size

        return CGSize(
            width: max(measuredSize.width, 1),
            height: max(measuredSize.height, 1)
        )
    }
}

struct WatchZoomableMathContainer<Content: View>: View {
    let latexMath: String
    let expandedFont: Math.Font
    var showsIndicator: Bool = false
    var accessibilityIdentifier: String = "math.zoom.trigger"
    var accessibilityLabel: String = "Math formula"
    var accessibilityHint: String = "Double tap to enlarge the equation."
    @ViewBuilder var content: () -> Content

    @State private var isShowingExpandedMath = false

    var body: some View {
        Button {
            isShowingExpandedMath = true
        } label: {
            content()
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityIdentifier(accessibilityIdentifier)
            .overlay(alignment: .topTrailing) {
                if showsIndicator {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $isShowingExpandedMath) {
                ExpandedWatchMathView(
                    latexMath: latexMath,
                    naturalSize: measuredMathSize(for: latexMath, font: expandedFont),
                    font: expandedFont
                )
            }
    }
}

private struct ExpandedWatchMathView: View {
    let latexMath: String
    let naturalSize: CGSize
    let font: Math.Font

    @Environment(\.dismiss) private var dismiss

    @State private var scrollContentMinX: CGFloat = 0

    private let horizontalPadding: CGFloat = 10
    private static let scrollCoordinateSpaceName = "math.zoom.expanded.scroll"

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(proxy.size.width - (horizontalPadding * 2), 1)
            let overflowWidth = max(naturalSize.width - viewportWidth, 0)
            let visibleOffset = min(max(-scrollContentMinX, 0), overflowWidth)

            ZStack {
                Color.black.opacity(0.96)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Spacer(minLength: 6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        Math(latexMath)
                            .mathFont(font)
                            .mathTypesettingStyle(.display)
                            .frame(width: naturalSize.width, height: naturalSize.height, alignment: .leading)
                            .background {
                                GeometryReader { contentProxy in
                                    Color.clear.preference(
                                        key: ExpandedMathScrollOffsetPreferenceKey.self,
                                        value: contentProxy.frame(in: .named(Self.scrollCoordinateSpaceName)).minX
                                    )
                                }
                            }
                    }
                    .coordinateSpace(name: Self.scrollCoordinateSpaceName)
                    .frame(width: viewportWidth, height: naturalSize.height, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zoomed formula viewport")
                    .accessibilityIdentifier("math.zoom.viewport")
                    .onPreferenceChange(ExpandedMathScrollOffsetPreferenceKey.self) { minX in
                        scrollContentMinX = minX
                    }

                    if overflowWidth > 0 {
                        Text("旋转表冠横向查看")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("math.zoom.close")

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(scrollAccessibilityValue(offset: Double(visibleOffset), overflowWidth: overflowWidth))
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("math.zoom.position")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("math.zoom.sheet")
        }
    }
}

private func scrollAccessibilityValue(offset: Double, overflowWidth: CGFloat) -> String {
    "offset:\(Int(offset.rounded()))/\(Int(overflowWidth.rounded()))"
}

func measuredMathSize(for latexMath: String, font: Math.Font) -> CGSize {
    let bounds = Math.typographicBounds(
        for: latexMath,
        fitting: ProposedViewSize(width: 10_000, height: nil),
        font: font,
        style: .display
    )
    let measuredSize = bounds.size

    return CGSize(
        width: max(measuredSize.width, 1),
        height: max(measuredSize.height, 1)
    )
}

private struct MathAvailableWidthPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ExpandedMathScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
