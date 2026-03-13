import SwiftUI

/// A type that renders markdown images.
///
/// Think of this type as a SwiftUI View wrapper.
@preconcurrency
@MainActor
@_typeEraser(AnyMarkdownImageRenderer)
public protocol MarkdownImageRenderer {
    /// A view that represents the current image.
    associatedtype Body: SwiftUI.View

    /// Creates a view that represents the body of the image.
    ///
    /// - Parameter configuration: The properties of an image.
    @preconcurrency
    @MainActor
    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of an image.
    typealias Configuration = MarkdownImageRendererConfiguration
}

/// The properties of a markdown image.
@preconcurrency
@MainActor
public struct MarkdownImageRendererConfiguration: Sendable {
    /// The image URL.
    public var url: URL
    /// The alt text of the image.
    public var alt: String?
}

// MARK: - Type Erasure

/// A type-erasure for type conforms to `MarkdownImageRenderer`.
public struct AnyMarkdownImageRenderer: MarkdownImageRenderer {
    public typealias Body = AnyView

    private let _makeBody: (Configuration) -> AnyView

    public init<T: MarkdownImageRenderer>(erasing renderer: T) {
        _makeBody = {
            AnyView(renderer.makeBody(configuration: $0))
        }
    }

    public init<T: MarkdownImageRenderer>(_ renderer: T) {
        _makeBody = {
            AnyView(renderer.makeBody(configuration: $0))
        }
    }

    public func makeBody(configuration: Configuration) -> Body {
        _makeBody(configuration)
    }
}
