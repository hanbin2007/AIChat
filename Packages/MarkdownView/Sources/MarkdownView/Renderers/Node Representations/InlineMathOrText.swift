//
//  InlineMathOrText.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/2/24.
//

import SwiftUI
import RegexBuilder
import SwiftUIMath

@preconcurrency
struct InlineMathOrText {
    var text: String

    enum ParsedItem {
        case math(Range<String.Index>)
        case issue(MathParser.FormatIssue)
    }

    enum Segment: Sendable, Hashable {
        case text(String)
        case math(String)
        case issue(rawLatex: String, message: String)
    }

    final class ParsedSegmentStore: @unchecked Sendable {
        static let shared = ParsedSegmentStore()

        private let lock = NSLock()
        private var caches: [String : [Segment]] = [:]

        func segments(for text: String) -> [Segment] {
            lock.lock()
            defer { lock.unlock() }

            if let cached = caches[text] {
                return cached
            }

            let parsedSegments = Self.makeSegments(for: text)
            caches[text] = parsedSegments
            return parsedSegments
        }

        private static func makeSegments(for text: String) -> [Segment] {
            let mathParser = MathParser(text: text)
            var segments: [Segment] = []
            var processingIndex = text.startIndex

            let parsedItems =
                mathParser.mathRepresentations
                .map { ParsedItem.math($0.range) } +
                mathParser.formatIssues
                .filter(\.kind.inline)
                .map(ParsedItem.issue)

            for item in parsedItems.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                let range = item.range

                if processingIndex < range.lowerBound {
                    let normalText = String(text[processingIndex..<range.lowerBound])
                    segments.append(.text(normalText))
                }

                switch item {
                case .math:
                    segments.append(.math(String(text[range])))
                case .issue(let issue):
                    segments.append(
                        .issue(
                            rawLatex: String(text[issue.range]),
                            message: issue.message
                        )
                    )
                }

                processingIndex = range.upperBound
            }

            if processingIndex < text.endIndex {
                let remainingText = String(text[processingIndex..<text.endIndex])
                segments.append(.text(remainingText))
            }

            return segments
        }
    }

    nonisolated static func prewarm(text: some StringProtocol) {
        _ = ParsedSegmentStore.shared.segments(for: String(text))
    }
    
    @preconcurrency
    @MainActor
    func makeBody(configuration: MarkdownRendererConfiguration) -> MarkdownNodeView {
        let parsedSegments = ParsedSegmentStore.shared.segments(for: text)
        var nodeViews: [MarkdownNodeView] = []

        for segment in parsedSegments {
            switch segment {
            case .text(let normalText):
                nodeViews.append(MarkdownNodeView(normalText))
            case .math(let latexText):
                nodeViews.append(
                    MarkdownNodeView {
                        InlineMath(latexText: latexText)
                    }
                )
            case .issue(let rawLatex, let message):
                nodeViews.append(
                    MarkdownNodeView {
                        InvalidMathView(
                            rawLatex: rawLatex,
                            error: .init(category: .format, message: message),
                            style: .inline
                        )
                    }
                )
            }
        }
        
        return MarkdownNodeView(nodeViews)
    }
}

private extension InlineMathOrText.ParsedItem {
    var range: Range<String.Index> {
        switch self {
        case .math(let range):
            return range
        case .issue(let issue):
            return issue.range
        }
    }

    var lowerBound: String.Index {
        range.lowerBound
    }
}

struct InlineMath: View {
    var latexText: String

    private var validationError: Math.ValidationError? {
        Math.validationError(for: latexText)
    }
    
    var body: some View {
        if let validationError {
            InvalidMathView(
                rawLatex: latexText,
                error: validationError,
                style: .inline
            )
        } else {
            #if os(watchOS)
            WatchZoomableMathContainer(
                latexMath: latexText,
                expandedFont: Math.Font(name: .latinModern, size: 24),
                accessibilityIdentifier: "math.zoom.trigger.inline",
                accessibilityHint: "Double tap to enlarge the formula."
            ) {
                fittedInlineMath
            }
            #else
            fittedInlineMath
            #endif
        }
    }

    @ViewBuilder
    private var fittedInlineMath: some View {
        ViewThatFits(in: .horizontal) {
            Math(latexText)
                .mathTypesettingStyle(.text)

            ScrollView(.horizontal) {
                Math(latexText)
                    .mathTypesettingStyle(.text)
            }
        }
    }
}
