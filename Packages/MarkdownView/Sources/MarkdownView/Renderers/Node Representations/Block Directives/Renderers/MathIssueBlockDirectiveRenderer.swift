import Foundation
import SwiftUI
import SwiftUIMath

struct MathIssueBlockDirectiveRenderer: BlockDirectiveRenderer {
    func makeBody(configuration: Configuration) -> some View {
        if let identifier = UUID(uuidString: configuration.arguments[0].value) {
            DisplayMathIssue(mathIssueIdentifier: identifier)
        } else {
            EmptyView()
        }
    }
}

private struct DisplayMathIssue: View {
    let mathIssueIdentifier: UUID

    @Environment(\.markdownRendererConfiguration.math) private var math

    private var issue: MarkdownRendererConfiguration.Math.RenderIssue? {
        math.displayMathIssueStorage?[mathIssueIdentifier]
    }

    var body: some View {
        if let issue {
            InvalidMathView(
                rawLatex: issue.rawValue,
                error: .init(category: .format, message: issue.message),
                style: .block
            )
        } else {
            EmptyView()
        }
    }
}
