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

    private let autoSendToWatch: Bool
    @State private var requestCode = ""
    @State private var requestIssuedAt = Date.now
    @State private var draftActivationCode = ""
    @State private var feedbackMessage: String?
    @State private var isSubmitting = false
    @State private var hasAttemptedAutomaticWatchTransfer = false

    init(
        prefilledActivationCode: String = "",
        autoSendToWatch: Bool = false
    ) {
        self.autoSendToWatch = autoSendToWatch
        _draftActivationCode = State(initialValue: prefilledActivationCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ActivationStatusCard(
                        title: chatStore.activationStatusTitle,
                        message: feedbackMessage ?? chatStore.companionActivationFeedbackMessage ?? chatStore.activationStatusMessage,
                        iconName: statusIconName,
                        accentColor: statusTintColor
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                onlineAccountSection
                onlinePlansSection
                recentUsageSection

                Section("当前设备") {
                    LabeledContent("设备码", value: chatStore.deviceIdentity.displayToken)
                    LabeledContent("请求有效", value: L10n.tr("common.duration.30m"))
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

                Section("Apple Watch 备用导入") {
                    LabeledContent("同步状态", value: chatStore.syncStatusDescription)

                    if let pairedWatchActivationRequestCode = chatStore.pairedWatchActivationRequestCode {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("最近来自手表的请求码")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(pairedWatchActivationRequestCode)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }

                        Button("复制手表请求码") {
                            UIPasteboard.general.string = pairedWatchActivationRequestCode
                        }
                    }

                    Button("从剪贴板粘贴激活码") {
                        let pastedValue = UIPasteboard.general.string ?? ""
                        let normalizedCode = OfflineActivation.normalizeActivationInput(pastedValue)
                        guard normalizedCode.isEmpty == false else {
                            feedbackMessage = L10n.tr("activation.feedback.no_code_in_clipboard")
                            return
                        }

                        draftActivationCode = OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
                    }
                    .disabled(isSubmitting)

                    Button("发送到 Apple Watch") {
                        Task {
                            await sendActivationCodeToWatch(draftActivationCode)
                        }
                    }
                    .disabled(isSubmitting || chatStore.canTransferActivationCodeToPairedWatch == false)

                    Text("手表端仍然可以独立输入激活码；这里仅作为备用快速导入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .onAppear {
                refreshRequestCode()
                attemptAutomaticWatchTransferIfNeeded()
                Task {
                    await chatStore.refreshRelayCatalog()
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("尚未绑定在线账户；首次启动会自动申请试用额度。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(requestAccessButtonTitle) {
                Task {
                    await requestManagedRelayAccess()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || chatStore.relayBillingBusy)

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
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.title)
                                .font(.headline)
                            Text("\(plan.monthlyCredits) credits / 月")
                                .font(.footnote)
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

                Text("iPhone 和 Apple Watch 都可以直接购买；购买完成后会通过 relay server 下发各自独立 key。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("套餐列表暂未加载。")
                    .font(.footnote)
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
                ForEach(usage.prefix(5), id: \.requestID) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.endpoint) • \(entry.modelID)")
                            .font(.subheadline.weight(.medium))
                        Text("in \(entry.inputTokens) • out \(entry.outputTokens) • \(entry.settledCredits) credits")
                            .font(.footnote)
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
    }

    private func applyActivationCode(_ rawCode: String) async {
        let normalizedCode = OfflineActivation.normalizeActivationInput(rawCode)
        guard normalizedCode.isEmpty == false else {
            feedbackMessage = L10n.tr("activation.feedback.enter_code")
            return
        }

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

    private func sendActivationCodeToWatch(_ rawCode: String) async {
        let normalizedCode = OfflineActivation.normalizeActivationInput(rawCode)
        guard normalizedCode.isEmpty == false else {
            feedbackMessage = L10n.tr("activation.feedback.enter_code")
            return
        }

        guard chatStore.canTransferActivationCodeToPairedWatch else {
            feedbackMessage = L10n.tr("activation.feedback.no_watch_channel")
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        chatStore.sendActivationCodeToPairedWatch(normalizedCode)
        draftActivationCode = OfflineActivation.formatActivationCodeForDisplay(normalizedCode)
        feedbackMessage = L10n.tr("activation.feedback.sent_to_watch")
    }

    private func attemptAutomaticWatchTransferIfNeeded() {
        guard autoSendToWatch else {
            return
        }

        guard hasAttemptedAutomaticWatchTransfer == false else {
            return
        }

        guard draftActivationCode.isEmpty == false else {
            return
        }

        hasAttemptedAutomaticWatchTransfer = true
        Task {
            await sendActivationCodeToWatch(draftActivationCode)
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

    private var requestAccessButtonTitle: String {
        guard let account = chatStore.relayAccountStatus?.account else {
            return "申请试用"
        }
        return account.state == .active && account.creditBalance > 0 ? "刷新在线权限" : "重新申请使用"
    }

    private func requestManagedRelayAccess() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let status = try await chatStore.requestManagedRelayAccess()
            feedbackMessage = relayAccessResultMessage(from: status)
        } catch {
            feedbackMessage = "申请失败：\(error.localizedDescription)"
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

    private func planTitle(_ planID: String?) -> String {
        guard let planID else {
            return "未订阅"
        }

        return chatStore.relayCatalog?.plans.first(where: { $0.id == planID })?.title ?? planID
    }
}
#endif
