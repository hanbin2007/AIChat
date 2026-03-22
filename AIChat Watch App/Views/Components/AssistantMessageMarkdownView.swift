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
        text.containsAssistantRenderableMath
    }

    private static func lineCount(in text: String) -> Int {
        text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}

private actor AssistantMessageMarkdownCache {
    static let shared = AssistantMessageMarkdownCache()

    private let capacity = 12
    private var cachedContents: [String: MarkdownContent] = [:]
    private var cacheOrder: [String] = []
    private var inFlightTasks: [String: Task<MarkdownContent, Never>] = [:]

    func cachedContent(for text: String) -> MarkdownContent? {
        guard let content = cachedContents[text] else {
            return nil
        }

        touch(text)
        return content
    }

    func preparedContent(for text: String) async -> MarkdownContent {
        if let cached = cachedContents[text] {
            touch(text)
            return cached
        }

        if let inFlightTask = inFlightTasks[text] {
            return await inFlightTask.value
        }

        let task = Task.detached(priority: .userInitiated) {
            let content = MarkdownContent(text)
            content.prewarm(renderMath: true, parseBlockDirectives: true)
            return content
        }
        inFlightTasks[text] = task

        let content = await task.value
        inFlightTasks[text] = nil
        insert(content, for: text)
        return content
    }

    private func touch(_ text: String) {
        cacheOrder.removeAll { $0 == text }
        cacheOrder.append(text)
    }

    private func insert(_ content: MarkdownContent, for text: String) {
        cachedContents[text] = content
        touch(text)

        while cacheOrder.count > capacity {
            let evictedKey = cacheOrder.removeFirst()
            cachedContents[evictedKey] = nil
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

    static func prewarmIfNeeded(for text: String) async {
        guard AssistantMessageMarkdownPreparationDecider.shouldPrepareOffMainThread(text) else {
            return
        }

        _ = await AssistantMessageMarkdownCache.shared.preparedContent(for: text)
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

        if let cachedContent = await AssistantMessageMarkdownCache.shared.cachedContent(for: currentText) {
            guard Task.isCancelled == false, currentText == text else {
                return
            }

            preparedContent = cachedContent
            preparedText = currentText
            return
        }

        let content = await AssistantMessageMarkdownCache.shared.preparedContent(for: currentText)

        guard Task.isCancelled == false, currentText == text else {
            return
        }

        preparedContent = content
        preparedText = currentText
    }
}
