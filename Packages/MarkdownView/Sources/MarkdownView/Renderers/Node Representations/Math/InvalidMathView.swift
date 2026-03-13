import SwiftUI
import SwiftUIMath

struct InvalidMathView: View {
    enum Style {
        case inline
        case block
    }

    let rawLatex: String
    let error: Math.ValidationError
    let style: Style

    var body: some View {
        VStack(alignment: .leading, spacing: style == .inline ? 4 : 6) {
            Text(title)
                .font(style == .inline ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(titleColor)

            Text(error.message)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(rawLatex)
                .font(.system(style == .inline ? .caption : .footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .padding(style == .inline ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(titleColor.opacity(0.45), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(titleColor.opacity(0.08))
                )
        )
    }

    private var title: String {
        switch error.category {
        case .format:
            return "Formula format issue"
        case .unsupported:
            return "Formula unsupported"
        }
    }

    private var titleColor: Color {
        switch error.category {
        case .format:
            return .yellow
        case .unsupported:
            return .orange
        }
    }
}
