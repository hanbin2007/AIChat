//
//  AssistantMessageMarkdownView.swift
//  AIChat Watch App
//
//  Switches between plain text and the `MarkdownView` package based on
//  `String.preferredAssistantMessageTextRenderingMode`. The decider in
//  `ChatModels.swift` returns `.plain` for short / non-formatted text
//  so we don't pay the markdown parser cost on every assistant chunk.
//
//  Math expressions ($$...$$, $...$, \(...\), \[...\]) are routed
//  through MarkdownView's `markdownMathRenderingEnabled(true)` path,
//  which delegates display math to `WatchAdaptiveDisplayMathView`
//  (auto-scales to wrist width + tap-to-expand zoom container). The
//  decider already detects math via `containsAssistantRenderableMath`,
//  so a math-only short message still gets the markdown route.
//

import SwiftUI
import MarkdownView

struct AssistantMessageMarkdownView: View {
    let text: String

    var body: some View {
        switch text.preferredAssistantMessageTextRenderingMode {
        case .plain:
            Text(text)
                .font(DS.Typography.bubbleBody)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .markdown:
            MarkdownView(text)
                .markdownMathRenderingEnabled(true)
                .font(DS.Typography.bubbleBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
