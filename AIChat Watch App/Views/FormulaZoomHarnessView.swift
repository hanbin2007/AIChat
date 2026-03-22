#if os(watchOS)
import SwiftUI

private let formulaHarnessConversationID =
    UUID(uuidString: "00000000-0000-0000-0000-00000000f001") ?? UUID()

struct FormulaZoomHarnessView: View {
    private let targetFormulaMarkdown =
        """
        答案是 **$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**。
        """

    private let longDisplayMathMarkdown =
        """
        $$
        \\sum_{i=1}^{24} \\frac{a_i + b_i + c_i + d_i + e_i}{\\sqrt{x_i^2 + y_i^2 + z_i^2 + w_i^2 + v_i^2}}
        =
        \\prod_{k=1}^{18} \\left(\\alpha_k + \\beta_k + \\gamma_k + \\delta_k\\right)
        $$
        """

    private let fullSolutionMarkdown =
        """
        已知 $a=1$，双曲线 $F$ 的方程为 $x^2 - \\frac{y^2}{b^2} = 1$。左右顶点分别为 $A_1(-1, 0)$，$A_2(1, 0)$。

        **1. 设点与直线方程**

        已知直线 $l$ 过点 $M(-2, 0)$，若 $l$ 为 $x$ 轴，则交点为顶点，代入题干向量条件不成立。因此可设直线 $l$ 的方程为 $x = my - 2$。设 $P(x_1, y_1)$，$Q(x_2, y_2)$。因为 $OQ$ 连线过原点 $O$ 且 $R$ 在双曲线上，根据双曲线的对称性，点 $R$ 与点 $Q$ 关于原点对称，即 $R(-x_2, -y_2)$。

        **2. 向量数量积条件转化**

        $\\overrightarrow{A_1R} = (1 - x_2, -y_2)$  
        $\\overrightarrow{A_2P} = (x_1 - 1, y_1)$

        由 $\\overrightarrow{A_1R} \\cdot \\overrightarrow{A_2P} = 1$，得：

        $(1 - x_2)(x_1 - 1) - y_1y_2 = 1$

        展开并整理得：

        $x_1 + x_2 - x_1x_2 - y_1y_2 = 2$ ……（式①）

        **3. 联立方程与韦达定理**

        将 $x = my - 2$ 代入 $b^2x^2 - y^2 = b^2$ 中，得：

        $(m^2b^2 - 1)y^2 - 4mb^2y + 3b^2 = 0$

        要使直线与双曲线交于两点，需满足二次项系数不为0，即 $m^2b^2 \\neq 1$。  
        判别式 $\\Delta = 4b^2(m^2b^2 + 3) > 0$ 恒成立。

        由韦达定理得：

        $y_1 + y_2 = \\frac{4mb^2}{m^2b^2 - 1}$  
        $y_1y_2 = \\frac{3b^2}{m^2b^2 - 1}$

        进而求出 $x$ 的关系：

        $x_1 + x_2 = m(y_1 + y_2) - 4 = \\frac{4}{m^2b^2 - 1}$  
        $x_1x_2 = (my_1 - 2)(my_2 - 2) = \\frac{-m^2b^2 - 4}{m^2b^2 - 1}$

        **4. 求解 $b$ 的取值范围**

        将上述式子代入（式①）中：

        $\\frac{4 - (-m^2b^2 - 4) - 3b^2}{m^2b^2 - 1} = 2$  
        $\\frac{m^2b^2 - 3b^2 + 8}{m^2b^2 - 1} = 2$

        化简解得：

        $m^2b^2 + 3b^2 = 10 \\implies b^2 = \\frac{10}{m^2 + 3}$

        因为 $m \\in \\mathbb{R}$，所以 $m^2 \\ge 0$，从而 $m^2 + 3 \\ge 3$。  
        因此 $0 < b^2 \\le \\frac{10}{3}$。  
        又因为需满足 $m^2b^2 \\neq 1$，即 $10 - 3b^2 \\neq 1$，解得 $b^2 \\neq 3$。

        综上所述，因为 $b > 0$，所以 $b$ 的取值范围为：

        **$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**
        """

    var body: some View {
        ZStack {
            AppBackdropView()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FormulaEvidenceCard(
                        title: "目标公式",
                        caption: nil,
                        markdown: targetFormulaMarkdown,
                        accessibilityIdentifier: "formula.zoom.last_formula.container"
                    )

                    FormulaEvidenceCard(
                        title: "长公式缩放",
                        caption: "保留一个 block math 场景，继续覆盖表冠横向查看。",
                        markdown: longDisplayMathMarkdown,
                        accessibilityIdentifier: "formula.zoom.display_formula.container"
                    )

                    FormulaEvidenceCard(
                        title: "完整原文",
                        caption: "保留整段推导内容，确保与实际消息渲染路径一致。",
                        markdown: fullSolutionMarkdown,
                        accessibilityIdentifier: "formula.zoom.full_content.container"
                    )
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
            }
            .accessibilityIdentifier("formula.zoom.harness")
        }
    }
}

private struct FormulaEvidenceCard: View {
    let title: String
    let caption: String?
    let markdown: String
    let accessibilityIdentifier: String

    private var previewMessage: ChatMessage {
        ChatMessage(role: .assistant, text: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }

            ChatBubbleView(
                conversationID: formulaHarnessConversationID,
                message: previewMessage,
                forceExpandedContent: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
#endif
