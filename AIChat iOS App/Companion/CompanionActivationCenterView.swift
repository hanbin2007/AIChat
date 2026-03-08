#if COMPANION_APP
//
//  CompanionActivationCenterView.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI
import UIKit

struct CompanionActivationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    @State private var requestCode = ""
    @State private var requestIssuedAt = Date.now
    @State private var draftActivationCode = ""
    @State private var feedbackMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ActivationStatusCard(
                        title: chatStore.activationStatusTitle,
                        message: feedbackMessage ?? chatStore.activationStatusMessage,
                        iconName: statusIconName,
                        accentColor: statusTintColor
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("当前设备") {
                    LabeledContent("设备码", value: chatStore.deviceIdentity.displayToken)
                    LabeledContent("请求有效", value: "30 分钟")
                    LabeledContent("生成时间", value: requestIssuedAt.formatted(date: .omitted, time: .shortened))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("请求码")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(requestCode)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }

                    Button("复制请求码") {
                        UIPasteboard.general.string = requestCode
                    }

                    Button("刷新请求码") {
                        refreshRequestCode()
                    }
                }

                Section("输入激活码") {
                    TextField("输入激活码", text: $draftActivationCode, axis: .vertical)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(isSubmitting)

                    Button("应用激活码") {
                        Task {
                            await applyActivationCode(draftActivationCode)
                        }
                    }
                    .disabled(isSubmitting)
                }

                if let licenseState {
                    Section("授权详情") {
                        LabeledContent("生效时间", value: licenseState.license.validFrom.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("到期时间", value: licenseState.license.validUntil?.formatted(date: .abbreviated, time: .shortened) ?? "长期")
                        LabeledContent("可用模型", value: allowedModelsText(for: licenseState.license.allowedModelIDs))
                        LabeledContent("次数限制", value: limitText(for: licenseState))
                    }
                }

                if chatStore.activationState != nil {
                    Section {
                        Button("清除当前授权", role: .destructive) {
                            Task {
                                await chatStore.clearActivation()
                                refreshRequestCode()
                                feedbackMessage = "已清除本机授权。"
                            }
                        }
                    }
                }
            }
            .navigationTitle("设备激活")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                refreshRequestCode()
            }
        }
    }

    private var licenseState: OfflineActivationState? {
        switch chatStore.activationStatus {
        case .pending(let state), .active(let state, _), .expired(let state), .exhausted(let state):
            return state
        case .inactive, .invalid:
            return nil
        }
    }

    private var statusIconName: String {
        switch chatStore.activationStatus {
        case .active:
            return "checkmark.seal.fill"
        case .pending:
            return "clock.badge.exclamationmark"
        case .expired, .exhausted, .invalid:
            return "exclamationmark.triangle.fill"
        case .inactive:
            return "lock.fill"
        }
    }

    private var statusTintColor: Color {
        switch chatStore.activationStatus {
        case .active:
            return .green
        case .pending:
            return .orange
        case .expired, .exhausted, .invalid:
            return .red
        case .inactive:
            return .orange
        }
    }

    private func refreshRequestCode() {
        requestIssuedAt = .now
        requestCode = chatStore.activationRequestCode(now: requestIssuedAt)
    }

    private func applyActivationCode(_ rawCode: String) async {
        let normalizedCode = OfflineActivation.normalizeActivationInput(rawCode)
        guard normalizedCode.isEmpty == false else {
            feedbackMessage = "请输入激活码。"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await chatStore.applyActivationCode(normalizedCode)
            draftActivationCode = OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
            refreshRequestCode()
            feedbackMessage = "激活成功，当前设备已解锁发送权限。"
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func allowedModelsText(for allowedModelIDs: Set<String>?) -> String {
        guard let allowedModelIDs else {
            return "全部"
        }

        let titles = LicensedModelCatalog.supportedModels
            .filter { allowedModelIDs.contains($0.id) }
            .map(\.title)

        return titles.isEmpty ? "全部" : titles.joined(separator: "、")
    }

    private func limitText(for state: OfflineActivationState) -> String {
        guard let messageLimit = state.license.messageLimit else {
            return "不限"
        }

        let remaining = state.remainingMessageCount ?? 0
        return "\(messageLimit) 次，总剩余 \(remaining) 次"
    }
}
#endif
