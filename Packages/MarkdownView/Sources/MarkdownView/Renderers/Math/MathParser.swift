//
//  MathParser.swift
//  MarkdownView
//
//  Created by LiYanan2004 on 2025/2/24.
//

import SwiftUI
#if canImport(LaTeXSwiftUI)
import LaTeXSwiftUI
import MathJaxSwift
#endif

/*
 Credits to colinc86/LaTeXSwiftUI
 */
@_spi(MarkdownMath)
public struct MathParser {
    public var text: any StringProtocol
    
    public init(text: some StringProtocol) {
        self.text = text
    }
    
    public var mathRepresentations: [MathRepresentation] {
        parseResult.mathRepresentations
    }

    public var formatIssues: [FormatIssue] {
        parseResult.formatIssues
    }

    private var parseResult: ParseResult {
        var currentDelimiter: DelimiterEntry?
        var index = text.startIndex
        var representations: [MathRepresentation] = []
        var formatIssues: [FormatIssue] = []

        inputLoop: while index < text.endIndex {
            let remaining = text[index...]

            if let activeDelimiter = currentDelimiter {
                let end = activeDelimiter.kind.rightTerminator
                if remaining.hasPrefix(end) {
                    if index > text.startIndex && text[text.index(before: index)] == "\\" {
                        index = text.index(index, offsetBy: end.count)
                        continue inputLoop
                    }

                    let endIndex = text.index(index, offsetBy: end.count)
                    representations.append(
                        MathRepresentation(
                            kind: activeDelimiter.kind,
                            range: activeDelimiter.startIndex..<endIndex
                        )
                    )
                    currentDelimiter = nil
                    index = endIndex
                    continue inputLoop
                }
            } else {
                for type in MathRepresentation.Kind.allCases {
                    let start = type.leftTerminator
                    if remaining.hasPrefix(start) {
                        if index > text.startIndex && text[text.index(before: index)] == "\\" {
                            index = text.index(index, offsetBy: start.count)
                            continue inputLoop
                        }

                        currentDelimiter = DelimiterEntry(
                            kind: type,
                            startIndex: index
                        )
                        index = text.index(index, offsetBy: start.count)
                        continue inputLoop
                    }
                }

                for type in MathRepresentation.Kind.allCases where type.shouldReportUnexpectedCloser {
                    let end = type.rightTerminator
                    if remaining.hasPrefix(end) {
                        if index > text.startIndex && text[text.index(before: index)] == "\\" {
                            index = text.index(index, offsetBy: end.count)
                            continue inputLoop
                        }

                        let endIndex = text.index(index, offsetBy: end.count)
                        formatIssues.append(
                            FormatIssue(
                                kind: type,
                                range: index..<endIndex,
                                message: "Unexpected closing delimiter \(end)"
                            )
                        )
                        index = endIndex
                        continue inputLoop
                    }
                }
            }

            index = text.index(after: index)
        }

        if let currentDelimiter, currentDelimiter.kind.shouldReportUnmatchedOpening {
            formatIssues.append(
                FormatIssue(
                    kind: currentDelimiter.kind,
                    range: currentDelimiter.startIndex..<text.endIndex,
                    message: "Missing closing delimiter \(currentDelimiter.kind.rightTerminator)"
                )
            )
        }

        return ParseResult(
            mathRepresentations: representations,
            formatIssues: formatIssues
        )
    }
}

extension MathParser {
    private struct ParseResult {
        var mathRepresentations: [MathRepresentation]
        var formatIssues: [FormatIssue]
    }

    private struct DelimiterEntry {
        var kind: MathRepresentation.Kind
        var startIndex: String.Index
    }

    public struct MathRepresentation: Sendable, Hashable {
        public var kind: Kind
        public var range: Range<String.Index>
    }

    public struct FormatIssue: Sendable, Hashable {
        public var kind: MathRepresentation.Kind
        public var range: Range<String.Index>
        public var message: String
    }
}

extension MathParser.MathRepresentation {
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// An inline equation component.
        ///
        /// - Example: `$x^2$`
        case inlineEquation
        
        /// An inline equation component.
        ///
        /// - Example: `\(x^2\)`
        case inlineParenthesesEquation
        
        /// A TeX-style block equation.
        ///
        /// - Example: `$$x^2$$`.
        case texEquation
        
        /// A block equation.
        ///
        /// - Example: `\[x^2\]`
        case blockEquation
        
        /// A named equation component.
        ///
        /// - Example: `\begin{equation}x^2\end{equation}`
        case namedEquation
        
        /// A named equation component.
        ///
        /// - Example: `\begin{equation*}x^2\end{equation*}`
        case namedNoNumberEquation
        
        /// The component's left terminator.
        var leftTerminator: String {
            switch self {
            case .inlineEquation: return "$"
            case .inlineParenthesesEquation: return "\\("
            case .texEquation: return "$$"
            case .blockEquation: return "\\["
            case .namedEquation: return "\\begin{equation}"
            case .namedNoNumberEquation: return "\\begin{equation*}"
            }
        }
        
        /// The component's right terminator.
        var rightTerminator: String {
            switch self {
            case .inlineEquation: return "$"
            case .inlineParenthesesEquation: return "\\)"
            case .texEquation: return "$$"
            case .blockEquation: return "\\]"
            case .namedEquation: return "\\end{equation}"
            case .namedNoNumberEquation: return "\\end{equation*}"
            }
        }
        
        /// Whether or not this component is inline.
        var inline: Bool {
            switch self {
            case .inlineEquation, .inlineParenthesesEquation: return true
            default: return false
            }
        }

        var shouldReportUnmatchedOpening: Bool {
            switch self {
            case .inlineEquation:
                return false
            default:
                return true
            }
        }

        var shouldReportUnexpectedCloser: Bool {
            switch self {
            case .inlineEquation:
                return false
            default:
                return true
            }
        }
        
        public static let allCases: [Kind] = [
            .namedNoNumberEquation,
            .namedEquation,
            .blockEquation,
            .texEquation,
            .inlineEquation,
            .inlineParenthesesEquation,
        ]
    }
}
