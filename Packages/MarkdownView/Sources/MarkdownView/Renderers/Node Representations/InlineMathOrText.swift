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
@MainActor
struct InlineMathOrText {
    var text: String

    enum ParsedItem {
        case math(Range<String.Index>)
        case issue(MathParser.FormatIssue)
    }
    
    @preconcurrency
    @MainActor
    func makeBody(configuration: MarkdownRendererConfiguration) -> MarkdownNodeView {
        let mathParser = MathParser(text: text)
        var nodeViews: [MarkdownNodeView] = []
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
                nodeViews.append(MarkdownNodeView(normalText))
            }

            switch item {
            case .math:
                let latexText = String(text[range])
                nodeViews.append(
                    MarkdownNodeView {
                        InlineMath(latexText: latexText)
                    }
                )
            case .issue(let issue):
                let rawLatex = String(text[issue.range])
                nodeViews.append(
                    MarkdownNodeView {
                        InvalidMathView(
                            rawLatex: rawLatex,
                            error: .init(category: .format, message: issue.message),
                            style: .inline
                        )
                    }
                )
            }

            processingIndex = range.upperBound
        }

        if processingIndex < text.endIndex {
            let remainingText = String(text[processingIndex..<text.endIndex])
            nodeViews.append(MarkdownNodeView(remainingText))
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
}
