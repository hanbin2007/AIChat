//
//  AssistantMessageMarkdownView.swift
//  AIChat Watch App
//
//  Switches between plain text and the `MarkdownView` package based on
//  `String.preferredAssistantMessageTextRenderingMode`. The decider in
//  `ChatModels.swift` returns `.plain` for short / non-formatted text
//  so we don't pay the markdown parser cost on every assistant chunk.
//
//  Math expressions ($$...$$ or \(...\)) are handled inside MarkdownView
//  via its bundled `SwiftUIMath` integration; we don't re-route here.
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
                .font(DS.Typography.bubbleBody)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
