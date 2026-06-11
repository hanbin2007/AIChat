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

                if chatStore.configuration.backendMode == .relay {
                    onlineAccountSection
                    onlinePlansSection
                    recentUsageSection
                }

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
                        LabeledContent("Credit 限额", value: limitText(for: licenseState))
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
            .navigationTitle("激活与订阅")
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
                if chatStore.configuration.backendMode == .relay {
                    Task {
                        await chatStore.refreshRelayCatalog()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var onlineAccountSection: some View {
        Section("在线账户") {
            if let account = chatStore.relayAccountStatus?.account {
                LabeledContent("来源", value: sourceText(chatStore.relayAccountStatus?.key?.source))
                LabeledContent("状态", value: accountStateText(account.state))
                LabeledContent("余额", value: "\(account.creditBalance) credits")
                LabeledContent("套餐", value: planTitle(account.planID))

                if let expiresAt = account.creditExpiresAt {
                    LabeledContent("最近到期", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let note = account.adminNote?.nonEmptyTrimmed {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("尚未绑定在线账户。点击下方按钮后会显式申请在线使用权限，并在这里返回结果。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(requestAccessButtonTitle) {
                Task {
                    await requestManagedRelayAccess()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || chatStore.relayBillingBusy)
            .accessibilityIdentifier("activation.request_access")

            Button("刷新状态") {
                Task {
                    await chatStore.refreshActivationState()
                }
            }
            .disabled(isSubmitting || chatStore.relayBillingBusy)

            Button("恢复购买") {
                Task {
                    await restoreRelayPurchases()
                }
            }
            .disabled(isSubmitting || chatStore.relayBillingBusy)
        }
    }

    @ViewBuilder
    private var onlinePlansSection: some View {
        Section("在线购买") {
            if let plans = chatStore.relayCatalog?.plans, plans.isEmpty == false {
                ForEach(plans) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.title)
                                    .font(.headline)
                                Text("\(plan.monthlyCredits) credits / 月")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Button(priceText(for: plan)) {
                                Task {
                                    await purchase(planID: plan.id)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSubmitting || chatStore.relayBillingBusy)
                        }
                    }
                }

                Text("购买成功后会自动同步到已配对设备，各设备使用独立 relay key，共享同一 credit 池。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("套餐列表暂未加载。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("加载套餐") {
                    Task {
                        await chatStore.refreshRelayCatalog()
                    }
                }
                .disabled(isSubmitting || chatStore.relayBillingBusy)
            }
        }
    }

    @ViewBuilder
    private var recentUsageSection: some View {
        if let usage = chatStore.relayAccountStatus?.recentUsage, usage.isEmpty == false {
            Section("最近用量") {
                ForEach(usage.prefix(3), id: \.requestID) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.endpoint) • \(entry.modelID)")
                            .font(.caption)
                        Text("in \(entry.inputTokens) • out \(entry.outputTokens) • \(entry.settledCredits) credits")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
        guard let creditLimit = state.license.creditLimit else {
            return L10n.tr("common.unlimited")
        }

        let remaining = state.remainingCredits ?? 0
        return L10n.format("activation.limit.remaining", creditLimit, remaining)
    }

    private func purchase(planID: String) async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch try await chatStore.purchaseRelayPlan(id: planID) {
            case .completed:
                feedbackMessage = "购买成功，在线额度已更新。"
            case .pending:
                feedbackMessage = "购买已提交，等待 App Store 确认。"
            case .cancelled:
                feedbackMessage = "已取消购买。"
            }
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private func restoreRelayPurchases() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            _ = try await chatStore.restoreRelayPurchases()
            feedbackMessage = "恢复完成，账户状态已刷新。"
        } catch {
            feedbackMessage = error.localizedDescription
        }
    }

    private var requestAccessButtonTitle: String {
        guard let account = chatStore.relayAccountStatus?.account else {
            return "申请使用"
        }

        return account.state == .active && account.creditBalance > 0 ? "刷新在线权限" : "重新申请使用"
    }

    private func requestManagedRelayAccess() async {
        isSubmitting = true
        defer { isSubmitting = false }

        chatStore.clearCompanionActivationFeedbackMessage()

        do {
            let status = try await chatStore.requestManagedRelayAccess()
            feedbackMessage = relayAccessResultMessage(from: status)
        } catch {
            feedbackMessage = "申请失败：\(error.localizedDescription)"
        }
    }

    private func priceText(for plan: RelayPlanCatalogItem) -> String {
        let amount = NSDecimalNumber(decimal: plan.priceUSD).doubleValue
        return String(format: "$%.2f", amount)
    }

    private func sourceText(_ source: RelayAccessSource?) -> String {
        switch source {
        case .trial:
            return "试用"
        case .subscription:
            return "订阅"
        case .offlineManual:
            return "离线导入"
        case .unknown, nil:
            return "unknown"
        }
    }

    private func accountStateText(_ state: RelayAccountState) -> String {
        switch state {
        case .active:
            return "可用"
        case .paused:
            return "已暂停"
        case .expired:
            return "已过期"
        case .inactive:
            return "未激活"
        case .unknown:
            return "未知状态"
        }
    }

    private func relayAccessResultMessage(from status: RelayAccountStatusResponse?) -> String {
        guard let account = status?.account else {
            return "申请已提交，但暂未返回账户状态。"
        }

        var parts = ["申请结果：\(accountStateText(account.state))", "余额 \(account.creditBalance) credits"]

        if let expiration = account.creditExpiresAt {
            parts.append("到期 \(expiration.formatted(date: .abbreviated, time: .shortened))")
        }

        if let note = account.adminNote?.nonEmptyTrimmed {
            parts.append(note)
        }

        return parts.joined(separator: " • ")
    }

    private func planTitle(_ planID: String?) -> String {
        guard let planID else {
            return "未订阅"
        }

        return chatStore.relayCatalog?.plans.first(where: { $0.id == planID })?.title ?? planID
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
