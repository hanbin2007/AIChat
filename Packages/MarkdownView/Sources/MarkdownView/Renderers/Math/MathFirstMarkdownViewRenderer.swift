//
//  MathFirstMarkdownViewRenderer.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/4/12.
//

import SwiftUI
import Markdown

struct MathFirstMarkdownViewRenderer: MarkdownViewRenderer {
    func makeBody(
        content: MarkdownContent,
        configuration: MarkdownRendererConfiguration
    ) -> some View {
        var configuration = configuration
        var rawText = content.raw.text
        
        var extractor = ParsingRangesExtractor()
        extractor.visit(content.parse(options: ParseOptions().union(.parseBlockDirectives)))
        for range in extractor.parsableRanges(in: rawText).reversed() {
            let segment = rawText[range]
            let segmentParser = MathParser(text: segment)
            var replacements: [(range: Range<String.Index>, replacement: String)] = []

            for math in segmentParser.mathRepresentations where !math.kind.inline {
                let mathIdentifier = configuration.math.appendDisplayMath(
                    rawText[math.range]
                )
                replacements.append(
                    (
                        range: math.range,
                        replacement: "@math(uuid:\(mathIdentifier))"
                    )
                )
            }

            for issue in segmentParser.formatIssues where !issue.kind.inline {
                let issueIdentifier = configuration.math.appendDisplayMathIssue(
                    rawValue: rawText[issue.range],
                    message: issue.message
                )
                replacements.append(
                    (
                        range: issue.range,
                        replacement: "@math-issue(uuid:\(issueIdentifier))"
                    )
                )
            }

            for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                rawText.replaceSubrange(
                    replacement.range,
                    with: replacement.replacement
                )
            }
        }
        
        let _content = MarkdownContent(raw: .plainText(rawText))
        return CmarkFirstMarkdownViewRenderer()
            .makeBody(content: _content, configuration: configuration)
    }
}
