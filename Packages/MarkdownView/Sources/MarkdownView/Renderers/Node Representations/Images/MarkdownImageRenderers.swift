import SwiftUI

@dynamicMemberLookup
final class MarkdownImageRenderers: @unchecked Sendable {
    static let shared: MarkdownImageRenderers = .init()

    private init() { }

    private var renderers: [String: any MarkdownImageRenderer] = [:]

    func addRenderer(_ renderer: some MarkdownImageRenderer, forURLScheme urlScheme: String) {
        renderers[urlScheme] = renderer
    }

    static func named(_ urlScheme: String) -> (any MarkdownImageRenderer)? {
        if let renderer = MarkdownImageRenderers.shared.renderers[urlScheme] {
            return renderer
        }

        let lowercaseScheme = urlScheme.lowercased()
        return MarkdownImageRenderers.shared
            .renderers
            .first(where: { $0.key.lowercased() == lowercaseScheme })?
            .value
    }

    subscript<T>(dynamicMember keyPath: KeyPath<[String: any MarkdownImageRenderer], T>) -> T {
        renderers[keyPath: keyPath]
    }
}
