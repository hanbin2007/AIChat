//
//  ActivationCenterView.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import SwiftUI

#if os(watchOS)
struct ActivationCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatStore: ChatStore

    @State private var requestCode = ""
    @State private var requestIssuedAt = Date.now
    @State private var draftActivationCode = ""
    @State private var feedbackMessage: String?
    @State private var isSubmitting = false
    @State private var isShowingActivationCodeEntry = false

    var body: some View {
        NavigationStack {
            List {
                ActivationStatusCard(
                    title: chatStore.activationStatusTitle,
                    message: feedbackMessage ?? chatStore.companionActivationFeedbackMessage ?? chatStore.activationStatusMessage,
                    iconName: statusIconName,
                    accentColor: statusTintColor
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                Section("当前设备") {
                    LabeledContent("设备码", value: chatStore.deviceIdentity.displayToken)
                    LabeledContent("请求有效", value: L10n.tr("common.duration.30m"))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("请求码")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(requestCode)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.black.opacity(0.28))
                            )

                        Text(
                            L10n.format(
                                "activation.request.generated_at",
                                requestIssuedAt.formatted(date: .omitted, time: .shortened)
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button("刷新请求码") {
                        refreshRequestCode()
                    }
                }

                Section("输入激活码") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("手动输入")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(draftActivationCode.isEmpty ? "尚未输入激活码" : OfflineActivation.formatActivationCodeForDisplay(draftActivationCode))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.black.opacity(0.28))
                            )

                        Text("打开一个只包含原生输入框的页面，避免当前列表布局影响点击和焦点。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(draftActivationCode.isEmpty ? "打开输入框" : "重新编辑激活码") {
                            isShowingActivationCodeEntry = true
                        }

                        Button("应用激活码") {
                            Task {
                                await applyActivationCode(draftActivationCode)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftActivationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if draftActivationCode.isEmpty == false {
                            Button("清空输入", role: .destructive) {
                                draftActivationCode = ""
                            }
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
                                feedbackMessage = L10n.tr("activation.feedback.cleared")
                            }
                        }
                    }
                }
            }
            .navigationTitle("离线激活")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingActivationCodeEntry) {
                ActivationCodeEntrySheet(draftActivationCode: $draftActivationCode)
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
        chatStore.publishActivationRequestCodeToCompanion(requestCode)
    }

    private func applyActivationCode(_ rawCode: String) async {
        let normalizedCode = OfflineActivation.normalizeActivationInput(rawCode)
        guard normalizedCode.isEmpty == false else {
            feedbackMessage = L10n.tr("activation.feedback.enter_code")
            return
        }

        chatStore.clearCompanionActivationFeedbackMessage()
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await chatStore.applyActivationCode(normalizedCode)
            draftActivationCode = OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
            refreshRequestCode()
            feedbackMessage = L10n.tr("activation.feedback.success")
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func allowedModelsText(for allowedModelIDs: Set<String>?) -> String {
        guard let allowedModelIDs else {
            return L10n.tr("common.all")
        }

        let titles = LicensedModelCatalog.supportedModels
            .filter { allowedModelIDs.contains($0.id) }
            .map(\.title)

        return titles.isEmpty ? L10n.tr("common.all") : titles.joined(separator: L10n.tr("list.separator"))
    }

    private func limitText(for state: OfflineActivationState) -> String {
        guard let messageLimit = state.license.messageLimit else {
            return L10n.tr("common.unlimited")
        }

        let remaining = state.remainingMessageCount ?? 0
        return L10n.format("activation.limit.remaining", messageLimit, remaining)
    }
}

private struct ActivationCodeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var draftActivationCode: String
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("输入激活码", text: $draftActivationCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isInputFocused)
                    .onChange(of: draftActivationCode) { _, newValue in
                        let normalizedCode = OfflineActivation.normalizeActivationInput(newValue)
                        if normalizedCode.isEmpty {
                            if newValue.isEmpty == false {
                                draftActivationCode = ""
                            }
                            return
                        }

                        let formattedCode = OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
                        if formattedCode != newValue {
                            draftActivationCode = formattedCode
                        }
                    }

                Button("完成") {
                    dismiss()
                }
            }
            .navigationTitle("输入激活码")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                isInputFocused = true
            }
        }
    }
}
#endif
