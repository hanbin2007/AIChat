import MarkdownView
import SwiftUI
import SwiftUIMath

struct AssistantMessageMarkdownView: View {
    let text: String

    private var mathFont: Math.Font {
        #if os(watchOS)
        Math.Font(name: .latinModern, size: 18)
        #else
        Math.Font(name: .latinModern, size: 20)
        #endif
    }

    var body: some View {
        MarkdownView(text)
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
}
