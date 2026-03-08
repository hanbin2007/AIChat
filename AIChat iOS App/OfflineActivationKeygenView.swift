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
    @State private var hasMessageLimit = true
    @State private var messageLimit = 200
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
            .onChange(of: requestCode) { _ in clearGeneratedState() }
            .onChange(of: validFrom) { _ in clearGeneratedState() }
            .onChange(of: validUntil) { _ in clearGeneratedState() }
            .onChange(of: hasExpiry) { _ in clearGeneratedState() }
            .onChange(of: hasMessageLimit) { _ in clearGeneratedState() }
            .onChange(of: messageLimit) { _ in clearGeneratedState() }
            .onChange(of: selectedModelIDs) { _ in clearGeneratedState() }
            .onChange(of: useAllModels) { _ in clearGeneratedState() }
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

            Toggle("限制发送次数", isOn: $hasMessageLimit)
            if hasMessageLimit {
                Stepper(value: $messageLimit, in: 1...Int(UInt16.max), step: 10) {
                    LabeledContent("消息次数", value: "\(messageLimit)")
                }
            }
        }
    }

    private var modelsSection: some View {
        cardSection("模型范围") {
            Toggle("全部模型", isOn: $useAllModels)
                .onChange(of: useAllModels) { useAll in
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

        guard hasMessageLimit == false || messageLimit > 0 else {
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
                messageLimit: hasMessageLimit ? messageLimit : nil,
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
}
