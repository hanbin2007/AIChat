#if os(watchOS)
import SwiftUI

struct FormulaZoomHarnessView: View {
    private let sampleMarkdown =
        """
        $$
        \\sum_{i=1}^{24} \\frac{a_i + b_i + c_i + d_i + e_i}{\\sqrt{x_i^2 + y_i^2 + z_i^2 + w_i^2 + v_i^2}}
        =
        \\prod_{k=1}^{18} \\left(\\alpha_k + \\beta_k + \\gamma_k + \\delta_k\\right)
        $$

        Inline test: $\\int_0^T \\frac{f(t) + g(t) + h(t)}{1 + t^2 + t^4} \\, dt = \\Theta(n^2)$
        """

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                AssistantMessageMarkdownView(text: sampleMarkdown)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
            }
            .accessibilityIdentifier("formula.zoom.harness")
        }
    }
}
#endif
