import MarkdownView
import SwiftUI
import SwiftUIMath

private enum AssistantMessageMarkdownPreparationDecider {
    static let asynchronousCharacterThreshold = 720
    static let asynchronousLineThreshold = 10

    static func shouldPrepareOffMainThread(_ text: String) -> Bool {
        guard text.isEmpty == false else {
            return false
        }

        if containsLaTeX(text) {
            return true
        }

        return text.count > asynchronousCharacterThreshold ||
            lineCount(in: text) > asynchronousLineThreshold
    }

    static func containsLaTeX(_ text: String) -> Bool {
        text.contains("$$") ||
        text.contains("\\(") ||
        text.contains("\\[") ||
        text.contains("\\begin{equation}") ||
        text.contains("\\begin{equation*}")
    }

    private static func lineCount(in text: String) -> Int {
        text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}

struct AssistantMessageMarkdownView: View {
    let text: String

    @State private var preparedContent: MarkdownContent?
    @State private var preparedText = ""

    private var mathFont: Math.Font {
        #if os(watchOS)
        Math.Font(name: .latinModern, size: 18)
        #else
        Math.Font(name: .latinModern, size: 20)
        #endif
    }

    private var shouldPrepareOffMainThread: Bool {
        AssistantMessageMarkdownPreparationDecider.shouldPrepareOffMainThread(text)
    }

    var body: some View {
        Group {
            if shouldPrepareOffMainThread {
                if let preparedContent, preparedText == text {
                    configuredMarkdownView(MarkdownView(preparedContent))
                } else {
                    loadingPlaceholder
                        .task(id: text) {
                            await prepareMarkdownContent()
                        }
                }
            } else {
                configuredMarkdownView(MarkdownView(text))
            }
        }
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.cyan)

            Text(
                AssistantMessageMarkdownPreparationDecider.containsLaTeX(text) ?
                "正在渲染公式" :
                "正在渲染内容"
            )
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func configuredMarkdownView<Content: View>(_ view: Content) -> some View {
        view
            .markdownMathRenderingEnabled()
            .codeBlockStyle(.default(lightTheme: "xcode", darkTheme: "dark"))
            .font(.body, for: .body)
            .font(.title3.weight(.semibold), for: .h1)
            .font(.headline.weight(.semibold), for: .h2)
            .font(.subheadline.weight(.semibold), for: .h3)
            .font(.subheadline.weight(.medium), for: .h4)
            .font(.subheadline, for: .h5)
            .font(.footnote, for: .h6)
            .font(.body, for: .blockQuote)
            .font(.system(.footnote, design: .monospaced), for: .codeBlock)
            .font(.footnote, for: .tableBody)
            .font(.footnote.weight(.semibold), for: .tableHeader)
            .tint(Color(red: 0.57, green: 0.82, blue: 0.97), for: .link)
            .tint(Color(red: 0.97, green: 0.73, blue: 0.40), for: .inlineCodeBlock)
            .tint(Color.white.opacity(0.7), for: .blockQuote)
            .mathFont(mathFont)
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func prepareMarkdownContent() async {
        let currentText = text
        preparedContent = nil
        preparedText = ""

        let content = await Task.detached(priority: .userInitiated) {
            let content = MarkdownContent(currentText)
            content.prewarm(renderMath: true, parseBlockDirectives: true)
            return content
        }.value

        guard Task.isCancelled == false, currentText == text else {
            return
        }

        preparedContent = content
        preparedText = currentText
    }
}
