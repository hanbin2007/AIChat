//
//  OfflineActivationKeygenView.swift
//  AIChat Keygen
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI
import UIKit

struct OfflineActivationKeygenView: View {
    @State private var requestCode = ""
    @State private var validFrom = Date.now
    @State private var hasExpiry = true
    @State private var validUntil = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var hasCreditLimit = true
    @State private var creditLimit = 200
    @State private var note = ""
    @State private var useAllModels = true
    @State private var selectedModelIDs = Set(LicensedModelCatalog.supportedModels.map(\.id))
    @State private var generatedCode = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                requestSection
                policySection
                modelsSection
                actionSection
                outputSection
                errorSection
                }
                .padding(16)
            }
            .navigationTitle("离线注册机")
            .onChange(of: requestCode) { clearGeneratedState() }
            .onChange(of: validFrom) { clearGeneratedState() }
            .onChange(of: validUntil) { clearGeneratedState() }
            .onChange(of: hasExpiry) { clearGeneratedState() }
            .onChange(of: hasCreditLimit) { clearGeneratedState() }
            .onChange(of: creditLimit) { clearGeneratedState() }
            .onChange(of: note) { clearGeneratedState() }
            .onChange(of: selectedModelIDs) { clearGeneratedState() }
            .onChange(of: useAllModels) { clearGeneratedState() }
        }
    }

    private var requestSection: some View {
        cardSection("手表请求码") {
            TextEditor(text: $requestCode)
                .frame(minHeight: 88)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

            if let decodedRequest {
                LabeledContent("设备码", value: decodedRequest.displayDeviceToken)
                LabeledContent("请求时间", value: decodedRequest.issuedAt.formatted(date: .abbreviated, time: .shortened))
            } else if normalizedRequestCode.isEmpty == false {
                Text(errorMessage ?? "请求码格式不正确")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var policySection: some View {
        cardSection("授权策略") {
            DatePicker("生效时间", selection: $validFrom)

            Toggle("包含到期时间", isOn: $hasExpiry)
            if hasExpiry {
                DatePicker("到期时间", selection: $validUntil, in: validFrom...)
            }

            Toggle("限制 Credit", isOn: $hasCreditLimit)
            if hasCreditLimit {
                Stepper(value: $creditLimit, in: 1...Int(UInt16.max), step: 10) {
                    LabeledContent("Credit 数", value: "\(creditLimit)")
                }
            }

            TextField("备注（仅运营侧记录，不写入激活码）", text: $note, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if hasCreditLimit {
                LabeledContent("Gemini 成本上限", value: usdText(estimatedGeminiCostUSD))
                LabeledContent("建议售价", value: usdText(suggestedRetailPriceUSD))
            }
        }
    }

    private var modelsSection: some View {
        cardSection("模型范围") {
            Toggle("全部模型", isOn: $useAllModels)
                .onChange(of: useAllModels) { _, useAll in
                    if useAll {
                        selectedModelIDs = Set(LicensedModelCatalog.supportedModels.map(\.id))
                    }
                }

            if useAllModels == false {
                ForEach(LicensedModelCatalog.supportedModels) { model in
                    Toggle(isOn: binding(for: model.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.title)
                            Text(model.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        cardSection("操作") {
            Button("生成激活码") {
                generateActivationCode()
            }
            .disabled(canGenerate == false)
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        if generatedCode.isEmpty == false {
            cardSection("激活码") {
                Text(generatedCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Button("复制激活码") {
                    UIPasteboard.general.string = generatedCode
                }
                .buttonStyle(.bordered)

                if let activationImportURL {
                    ShareLink(item: activationImportURL) {
                        Label("分享导入链接", systemImage: "message")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage, generatedCode.isEmpty {
            cardSection("错误") {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
    }

    private func cardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private var normalizedRequestCode: String {
        OfflineActivation.normalize(requestCode)
    }

    private var decodedRequest: OfflineActivationRequest? {
        try? OfflineActivation.decodeRequestCode(normalizedRequestCode)
    }

    private var canGenerate: Bool {
        guard decodedRequest != nil else {
            return false
        }

        guard useAllModels || selectedModelIDs.isEmpty == false else {
            return false
        }

        guard hasCreditLimit == false || creditLimit > 0 else {
            return false
        }

        return hasExpiry == false || validUntil >= validFrom
    }

    private func binding(for modelID: String) -> Binding<Bool> {
        Binding(
            get: { selectedModelIDs.contains(modelID) },
            set: { isSelected in
                if isSelected {
                    selectedModelIDs.insert(modelID)
                } else {
                    selectedModelIDs.remove(modelID)
                }
            }
        )
    }

    private func clearGeneratedState() {
        generatedCode = ""
        errorMessage = nil
    }

    private func generateActivationCode() {
        generatedCode = ""
        errorMessage = nil

        do {
            let policy = OfflineActivationPolicy(
                validFrom: validFrom,
                validUntil: hasExpiry ? validUntil : nil,
                messageLimit: hasCreditLimit ? creditLimit : nil,
                allowedModelIDs: useAllModels ? nil : selectedModelIDs
            )
            generatedCode = try OfflineActivation.makeActivationCode(
                requestCode: normalizedRequestCode,
                policy: policy
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var activationImportURL: URL? {
        guard generatedCode.isEmpty == false else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "aichat"
        components.host = "activation"
        components.path = "/import"
        components.queryItems = [
            URLQueryItem(name: "code", value: generatedCode)
        ]

        return components.url
    }

    private var estimatedGeminiCostUSD: Decimal {
        Decimal(hasCreditLimit ? creditLimit : 0) / 1000
    }

    private var suggestedRetailPriceUSD: Decimal {
        roundUpToPricePoint(estimatedGeminiCostUSD / Decimal(string: "0.55")!)
    }

    private func roundUpToPricePoint(_ value: Decimal) -> Decimal {
        guard value > 0 else {
            return 0
        }

        let number = NSDecimalNumber(decimal: value).doubleValue
        let rounded = ceil(number - 0.99)
        let candidate = max(0.99, rounded + 0.99)
        return Decimal(candidate)
    }

    private func usdText(_ value: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}
