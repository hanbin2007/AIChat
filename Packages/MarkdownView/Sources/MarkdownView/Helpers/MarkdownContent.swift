//
//  MarkdownContent.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/2/9.
//

import Foundation
@preconcurrency import Markdown

// MARK: - Raw

enum RawMarkdownContent: Sendable, Hashable {
    case plainText(String)
    case url(URL)
    
    public var text: String {
        switch self {
        case .plainText(let text):
            return text
        case .url(let url):
            return (try? String(contentsOf: url)) ?? ""
        }
    }
    
    public var source: URL? {
        if case .url(let url) = self {
            return url
        }
        return nil
    }
}

// MARK: - Parsed Content

/// A Sendable markdown content that can be used to render content and supports on-demand parsing.
public struct MarkdownContent: Sendable {
    struct PreparedMathContent: Sendable, Hashable {
        var content: MarkdownContent
        var displayMathStorage: [UUID : String]
        var displayMathIssueStorage: [UUID : MarkdownRendererConfiguration.Math.RenderIssue]
    }

    private struct MathPreparationKey: Hashable {
        var parseOptionsRawValue: ParseOptions.RawValue
    }

    var raw: RawMarkdownContent
    
    class ParsedDocumentStore: /* NSLock */ @unchecked Sendable {
        private var lock = NSLock()
        private var caches: [ParseOptions.RawValue : Document] = [:]
        private var preparedMathCaches: [MathPreparationKey : PreparedMathContent] = [:]
        
        fileprivate func parse(_ rawContent: RawMarkdownContent, options: ParseOptions = ParseOptions()) -> Document {
            lock.lock()
            defer { lock.unlock() }
            
            return parseLocked(rawContent, options: options)
        }

        fileprivate func preparedMathContent(
            _ rawContent: RawMarkdownContent,
            options: ParseOptions = ParseOptions()
        ) -> PreparedMathContent {
            lock.lock()
            defer { lock.unlock() }

            let key = MathPreparationKey(parseOptionsRawValue: options.rawValue)
            if let cached = preparedMathCaches[key] {
                return cached
            }

            let prepared = Self.prepareMathContent(
                rawContent,
                parsedDocument: parseLocked(rawContent, options: options)
            )
            preparedMathCaches[key] = prepared
            return prepared
        }
        
        var documents: LazySequence<Dictionary<ParseOptions.RawValue, Document>.Values> {
            lock.withLock {
                caches.values.lazy
            }
        }
        
        var hasParsedDocument: Bool {
            !documents.isEmpty
        }

        private func parseLocked(
            _ rawContent: RawMarkdownContent,
            options: ParseOptions
        ) -> Document {
            if let cached = caches[options.rawValue] {
                return cached
            }

            let document = Document(
                parsing: rawContent.text,
                source: rawContent.source,
                options: options
            )
            caches[options.rawValue] = document
            return document
        }

        private static func prepareMathContent(
            _ rawContent: RawMarkdownContent,
            parsedDocument: Document
        ) -> PreparedMathContent {
            var rawText = rawContent.text
            var extractor = MathFirstMarkdownViewRenderer.ParsingRangesExtractor()
            extractor.visit(parsedDocument)

            var displayMathStorage: [UUID : String] = [:]
            var displayMathIssueStorage: [UUID : MarkdownRendererConfiguration.Math.RenderIssue] = [:]

            for range in extractor.parsableRanges(in: rawText).reversed() {
                let segment = rawText[range]
                let segmentParser = MathParser(text: segment)
                var replacements: [(range: Range<String.Index>, replacement: String)] = []

                for math in segmentParser.mathRepresentations where math.kind.inline == false {
                    let identifier = UUID()
                    displayMathStorage[identifier] = String(rawText[math.range])
                    replacements.append(
                        (
                            range: math.range,
                            replacement: "@math(uuid:\(identifier.uuidString))"
                        )
                    )
                }

                for issue in segmentParser.formatIssues where issue.kind.inline == false {
                    let identifier = UUID()
                    displayMathIssueStorage[identifier] = MarkdownRendererConfiguration.Math.RenderIssue(
                        rawValue: String(rawText[issue.range]),
                        message: issue.message
                    )
                    replacements.append(
                        (
                            range: issue.range,
                            replacement: "@math-issue(uuid:\(identifier.uuidString))"
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

            return PreparedMathContent(
                content: MarkdownContent(raw: .plainText(rawText)),
                displayMathStorage: displayMathStorage,
                displayMathIssueStorage: displayMathIssueStorage
            )
        }
    }
    var store: ParsedDocumentStore
    
    public init(_ text: String) {
        self.raw = .plainText(text)
        self.store = ParsedDocumentStore()
    }

    internal init(raw: RawMarkdownContent) {
        self.raw = raw
        self.store = ParsedDocumentStore()
    }
    
    func parse(options: ParseOptions = ParseOptions()) -> Document {
        store.parse(raw, options: options)
    }

    func preparedMathContent(options: ParseOptions = ParseOptions()) -> PreparedMathContent {
        store.preparedMathContent(raw, options: options)
    }

    public func prewarm(
        renderMath: Bool = false,
        parseBlockDirectives: Bool = false
    ) {
        let options =
            parseBlockDirectives ?
            ParseOptions().union(.parseBlockDirectives) :
            ParseOptions()

        if renderMath {
            let prepared = preparedMathContent(options: options)
            let document = prepared.content.parse(options: options)
            var prewarmer = InlineMathTextPrewarmer()
            prewarmer.visit(document)
            return
        }

        _ = parse(options: options)
    }
}

extension MarkdownContent: Hashable {
    public static func == (lhs: MarkdownContent, rhs: MarkdownContent) -> Bool {
        lhs.raw == rhs.raw
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(raw)
    }
}

private struct InlineMathTextPrewarmer: MarkupWalker {
    mutating func defaultVisit(_ markup: any Markup) {
        descendInto(markup)
    }

    mutating func visitText(_ text: Markdown.Text) {
        InlineMathOrText.prewarm(text: text.plainText)
    }
}
