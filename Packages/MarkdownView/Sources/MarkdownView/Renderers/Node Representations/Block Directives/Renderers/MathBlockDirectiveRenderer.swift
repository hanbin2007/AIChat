//
//  MathBlockDirectiveRenderer.swift
//  MarkdownView
//
//  Created by Yanan Li on 2025/4/12.
//

import Foundation
import SwiftUI
import SwiftUIMath

struct MathBlockDirectiveRenderer: BlockDirectiveRenderer {
    func makeBody(configuration: Configuration) -> some View {
        if let identifier = UUID(uuidString: configuration.arguments[0].value) {
            DisplayMath(mathIdentifier: identifier)
        } else {
            EmptyView()
        }
    }
}

fileprivate struct DisplayMath: View {
    var mathIdentifier: UUID
    @Environment(\.markdownRendererConfiguration.math) private var math

    private var latexMath: String? {
        math.displayMathStorage?[mathIdentifier]
    }

    private var validationError: Math.ValidationError? {
        guard let latexMath else {
            return nil
        }
        return Math.validationError(for: latexMath)
    }

    var body: some View {
        if let latexMath, let validationError {
            InvalidMathView(
                rawLatex: latexMath,
                error: validationError,
                style: .block
            )
        } else {
            ViewThatFits(in: .horizontal) {
                latex

                ScrollView(.horizontal) {
                    latex
                }
            }
        }
    }
    
    @ViewBuilder
    private var latex: some View {
        if let latexMath {
            Math(latexMath)
                .mathTypesettingStyle(.display)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
