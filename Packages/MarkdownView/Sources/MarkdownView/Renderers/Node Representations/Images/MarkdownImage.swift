import Markdown
import SwiftUI

struct MarkdownImage: View {
    let image: Markdown.Image

    @Environment(\.markdownRendererConfiguration) private var configuration

    var body: some View {
        Group {
            if let resolvedURL {
                if let scheme = resolvedURL.scheme,
                   configuration.allowedImageRenderers.contains(scheme),
                   let renderer = MarkdownImageRenderers.named(scheme) {
                    renderer.makeBody(
                        configuration: .init(url: resolvedURL, alt: altText)
                    )
                    .erasedToAnyView()
                } else {
                    DefaultMarkdownImage(url: resolvedURL, altText: altText)
                }
            } else if let altText, !altText.isEmpty {
                Text(altText)
            } else {
                EmptyView()
            }
        }
    }

    private var altText: String? {
        let text = image.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var resolvedURL: URL? {
        guard let source = image.source, !source.isEmpty else {
            return nil
        }

        if let absoluteURL = URL(string: source), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if let preferredBaseURL = configuration.preferredBaseURL {
            return URL(string: source, relativeTo: preferredBaseURL)?.absoluteURL
        }

        return URL(filePath: source)
    }
}

private struct DefaultMarkdownImage: View {
    let url: URL
    let altText: String?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                fallbackLabel
            default:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .accessibilityLabel(altText ?? url.lastPathComponent)
    }

    private var fallbackLabel: some View {
        Group {
            if let altText, !altText.isEmpty {
                Text(altText)
            } else {
                Label(url.lastPathComponent, systemImage: "photo")
            }
        }
    }
}
