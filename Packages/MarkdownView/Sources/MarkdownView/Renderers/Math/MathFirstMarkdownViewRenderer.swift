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
        let prepared = content.preparedMathContent(
            options: ParseOptions().union(.parseBlockDirectives)
        )
        configuration.math.displayMathStorage = prepared.displayMathStorage
        configuration.math.displayMathIssueStorage = prepared.displayMathIssueStorage

        return CmarkFirstMarkdownViewRenderer()
            .makeBody(content: prepared.content, configuration: configuration)
    }
}
