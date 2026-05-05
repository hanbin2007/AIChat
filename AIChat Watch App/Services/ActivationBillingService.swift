//
//  ActivationBillingService.swift
//  AIChat Watch App
//
//  Extracted from ChatStore — activation, licensing, and relay billing logic.
//

import Combine
import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
final class ActivationBillingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var activationState: OfflineActivationState?
    @Published private(set) var relayAccountStatus: RelayAccountStatusResponse?
    @Published private(set) var relayCatalog: RelayCatalogResponse?
    @Published private(set) var relayBillingBusy = false
    @Published private(set) var pairedWatchActivationRequestCode: String?
    @Published private(set) var companionActivationFeedbackMessage: String?

    // MARK: - Dependencies

    let configuration: AppConfiguration
    let deviceIdentity: WatchDeviceIdentity

    private let activationRepository: ActivationRepository
    private let relayAccessRepository: RelayAccessRepository
    private let relayAccountService: RelayAccountService
    private let syncBridge: CompanionSyncBridge
    private var lastHandledCompanionActivationTransferID: String?

    // MARK: - Init

    init(
        configuration: AppConfiguration,
        deviceIdentity: WatchDeviceIdentity,
        activationRepository: ActivationRepository,
        relayAccessRepository: RelayAccessRepository,
        syncBridge: CompanionSyncBridge
    ) {
        self.configuration = configuration
        self.deviceIdentity = deviceIdentity
        self.activationRepository = activationRepository
        self.relayAccessRepository = relayAccessRepository
        self.syncBridge = syncBridge
        self.relayAccountService = RelayAccountService(
            configuration: configuration,
            deviceIdentity: deviceIdentity,
            repository: relayAccessRepository
        )
    }

    // MARK: - Computed Properties

    var activationStatus: OfflineActivationStatus {
        OfflineActivation.status(for: activationState, deviceToken: deviceIdentity.deviceToken)
    }

    var relayAccessStatusTitle: String? {
        guard configuration.backendMode == .relay,
              let account = relayAccountStatus?.account
        else {
            return nil
        }

        switch account.state {
        case .active:
            if let expiresAt = account.creditExpiresAt, expiresAt <= .now {
                return "已过期"
            }
            if account.creditBalance > 0 {
                return "在线可用"
            }
            return "额度用尽"
        case .paused:
            return "已暂停"
        case .expired:
            return "已过期"
        case .inactive:
            return "未激活"
        }
    }

    var relayAccessStatusMessage: String? {
        guard configuration.backendMode == .relay,
              let account = relayAccountStatus?.account
        else {
            return nil
        }

        var parts: [String] = []
        if let source = relayAccountStatus?.key?.source {
            parts.append(relaySourceLabel(for: source))
        }
        parts.append("\(account.creditBalance) credits")

        if let expiration = account.creditExpiresAt {
            parts.append("到期 \(expiration.formatted(date: .abbreviated, time: .shortened))")
        }

        if let note = account.adminNote?.nonEmptyTrimmed {
            parts.append(note)
        }

        return parts.joined(separator: " • ")
    }

    var hasManagedRelayAccess: Bool {
        isManagedRelayAccessActive(for: relayAccountStatus)
    }

    var isReadOnlyMode: Bool {
        if hasManagedRelayAccess {
            return false
        }

        switch activationStatus {
        case .active:
            return false
        case .inactive, .pending, .expired, .exhausted, .invalid:
            return true
        }
    }

    var activationStatusTitle: String {
        if let relayAccessStatusTitle {
            return relayAccessStatusTitle
        }

        switch activationStatus {
        case .inactive:
            return L10n.tr("activation.status.inactive")
        case .pending:
            return L10n.tr("activation.status.pending")
        case .active:
            return L10n.tr("activation.status.active")
        case .expired:
            return L10n.tr("activation.status.expired")
        case .exhausted:
            return L10n.tr("activation.status.exhausted")
        case .invalid:
            return L10n.tr("activation.status.invalid")
        }
    }

    var activationStatusMessage: String {
        if let relayAccessStatusMessage {
            return relayAccessStatusMessage
        }

        switch activationStatus {
        case .inactive:
            return L10n.tr("activation.message.inactive")
        case .pending(let state):
            return OfflineActivationError.notYetActive(startDate: state.license.validFrom).localizedDescription
        case .active(let state, let remainingMessages):
            var components: [String] = []
            if let validUntil = state.license.validUntil {
                components.append(
                    L10n.format(
                        "activation.message.active.valid_until",
                        validUntil.formatted(date: .abbreviated, time: .shortened)
                    )
                )
            } else {
                components.append(L10n.tr("activation.message.active.forever"))
            }

            if let remainingMessages {
                components.append(L10n.format("activation.message.active.remaining", remainingMessages))
            } else {
                components.append(L10n.tr("activation.message.active.unlimited"))
            }

            components.append(
                L10n.format(
                    "activation.message.active.models",
                    allowedModelsDescription(for: state.license.allowedModelIDs)
                )
            )
            return components.joined(separator: " • ")
        case .expired(let state):
            if let validUntil = state.license.validUntil {
                return L10n.format(
                    "activation.message.expired.with_date",
                    validUntil.formatted(date: .abbreviated, time: .shortened)
                )
            }
            return L10n.tr("activation.message.expired.no_date")
        case .exhausted(let state):
            return L10n.format(
                "activation.message.exhausted",
                state.license.creditLimit ?? 0
            )
        case .invalid(let message):
            return message
        }
    }

    var activationAllowedModelIDs: Set<String>? {
        if hasManagedRelayAccess {
            return nil
        }

        return OfflineActivation.allowedModelIDs(
            for: activationState,
            deviceToken: deviceIdentity.deviceToken
        )
    }

    var canTransferActivationCodeToPairedWatch: Bool {
        switch syncBridge.currentStatus {
        case .idle, .reachable:
            return true
        case .unavailable, .notPaired, .companionMissing:
            return false
        }
    }

    // MARK: - Public Methods

    func refreshActivationState() async {
        activationState = activationRepository.loadState()
        relayAccountStatus = await relayAccessRepository.loadState()?.status

        guard configuration.backendMode == .relay else {
            return
        }

        do {
            let status = try await relayAccountService.fetchAccountStatusIfPossible()
            if status != nil {
                await updateRelayAccountStatus(status, shareToCompanion: true)
            }
        } catch {
            // Silently ignore fetch errors when we already have a status;
            // the caller (ChatStore) handles startupError propagation.
        }
    }

    func activationRequestCode(now: Date = .now) -> String {
        OfflineActivation.makeRequestCode(deviceToken: deviceIdentity.deviceToken, now: now)
    }

    func publishActivationRequestCodeToCompanion(_ requestCode: String) {
        syncBridge.pushActivationRequestCode(requestCode)
    }

    func applyActivationCode(_ rawCode: String, now: Date = .now) async throws {
        let nextState = try OfflineActivation.activate(
            code: rawCode,
            deviceToken: deviceIdentity.deviceToken,
            now: now,
            currentState: activationState
        )
        try activationRepository.saveState(nextState)
        activationState = nextState

        if configuration.backendMode == .relay {
            let status = try await relayAccountService.exchangeOfflineActivation(
                code: rawCode,
                state: nextState
            )
            await updateRelayAccountStatus(status, shareToCompanion: true)
        }
    }

    func clearActivation() throws {
        try activationRepository.clearState()
        activationState = nil
    }

    func setActivationStateForPreview(_ state: OfflineActivationState?) {
        activationState = state
    }

    func sendActivationCodeToPairedWatch(_ rawCode: String) {
        syncBridge.pushActivationCodeImport(rawCode)
    }

    func clearCompanionActivationFeedbackMessage() {
        companionActivationFeedbackMessage = nil
    }

    func refreshRelayCatalog() async throws {
        guard configuration.backendMode == .relay else {
            return
        }

        relayCatalog = try await relayAccountService.fetchCatalog()
    }

    @discardableResult
    func requestManagedRelayAccess() async throws -> RelayAccountStatusResponse? {
        guard configuration.backendMode == .relay else {
            return nil
        }

        let status = try await relayAccountService.refreshOrBootstrapStatus(forceBootstrap: true)
        await updateRelayAccountStatus(status, shareToCompanion: true)
        return status
    }

    @discardableResult
    func purchaseRelayPlan(id planID: String) async throws -> RelayStorePurchaseOutcome {
        guard configuration.backendMode == .relay else {
            throw RelayAPIError.missingConfiguration
        }

        relayBillingBusy = true
        defer { relayBillingBusy = false }

        if relayCatalog == nil {
            relayCatalog = try await relayAccountService.fetchCatalog()
        }

        guard let plan = relayCatalog?.plans.first(where: { $0.id == planID }) else {
            throw RelayAPIError.invalidResponse
        }

        #if canImport(StoreKit)
        let purchasePreparation = try await relayAccountService.preparePurchase()
        let products = try await Product.products(for: [plan.productID])
        guard let product = products.first(where: { $0.id == plan.productID }) else {
            throw RelayAPIError.storeKitProductUnavailable(productID: plan.productID)
        }

        let result = try await product.purchase(
            options: Set([Product.PurchaseOption.appAccountToken(purchasePreparation.appAccountToken)])
        )

        switch result {
        case .success(let verificationResult):
            let transaction = try verifiedStoreTransaction(from: verificationResult)
            let status = try await relayAccountService.submitPurchase(
                transaction: submittedTransaction(
                    from: transaction,
                    signedTransactionInfo: verificationResult.jwsRepresentation
                )
            )
            await updateRelayAccountStatus(status, shareToCompanion: true)
            await transaction.finish()
            return .completed
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
        #else
        throw RelayAPIError.missingConfiguration
        #endif
    }

    @discardableResult
    func restoreRelayPurchases() async throws -> RelayAccountStatusResponse? {
        guard configuration.backendMode == .relay else {
            return nil
        }

        relayBillingBusy = true
        defer { relayBillingBusy = false }

        #if canImport(StoreKit)
        try await AppStore.sync()

        var submittedTransactions: [RelaySubmittedTransaction] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else {
                continue
            }
            submittedTransactions.append(
                submittedTransaction(
                    from: transaction,
                    signedTransactionInfo: entitlement.jwsRepresentation
                )
            )
        }

        let status = try await relayAccountService.restorePurchases(transactions: submittedTransactions)
        await updateRelayAccountStatus(status, shareToCompanion: true)
        return status
        #else
        throw RelayAPIError.missingConfiguration
        #endif
    }

    // MARK: - Licensing Helpers (called by ChatStore)

    func licensedConfiguration(from configuration: ConversationAIConfiguration) -> ConversationAIConfiguration {
        if hasManagedRelayAccess {
            return configuration
        }

        var resolvedConfiguration = configuration
        resolvedConfiguration.model = OfflineActivation.recommendedModel(
            preferredModelID: configuration.model,
            defaultModelID: self.configuration.geminiModel,
            state: activationState,
            deviceToken: deviceIdentity.deviceToken
        )
        return resolvedConfiguration
    }

    func activationFailureMessage(for modelID: String) -> String? {
        if configuration.backendMode == .relay {
            if hasManagedRelayAccess {
                return nil
            }

            guard let account = relayAccountStatus?.account else {
                return "正在验证在线状态，请稍候…"
            }

            switch account.state {
            case .active:
                if let expiresAt = account.creditExpiresAt, expiresAt <= .now {
                    return "订阅或 credit 已过期。"
                }
                return account.creditBalance > 0 ? nil : "在线额度已用尽。"
            case .paused:
                return "当前 relay key 已在服务端暂停。"
            case .expired:
                return "订阅或 credit 已过期。"
            case .inactive:
                return "当前设备尚未完成在线激活。"
            }
        }

        switch activationStatus {
        case .inactive:
            return OfflineActivationError.notActivated.localizedDescription
        case .pending(let state):
            return OfflineActivationError.notYetActive(startDate: state.license.validFrom).localizedDescription
        case .expired:
            return OfflineActivationError.licenseExpired.localizedDescription
        case .exhausted:
            return OfflineActivationError.messageLimitReached.localizedDescription
        case .invalid(let message):
            return message
        case .active(let state, _):
            return state.license.allows(modelID: modelID) ? nil : OfflineActivationError.modelNotAllowed.localizedDescription
        }
    }

    func consumeActivationMessage(for modelID: String) throws {
        guard hasManagedRelayAccess == false else {
            return
        }

        let nextActivationState = try OfflineActivation.consumeMessage(
            from: activationState,
            deviceToken: deviceIdentity.deviceToken,
            modelID: modelID
        )

        if nextActivationState != activationState {
            try activationRepository.saveState(nextActivationState)
            activationState = nextActivationState
        }
    }

    // MARK: - Sync Event Handling

    func handleActivationSyncEvent(_ event: CompanionSyncEvent) async {
        switch event {
        case .activationRequestCode(let requestCode):
            #if os(iOS)
            pairedWatchActivationRequestCode = OfflineActivation.formatForDisplay(requestCode, groupSize: 4)
            #endif
        case .activationCodeImport(let code, let transferID):
            #if os(watchOS)
            if let transferID, transferID == lastHandledCompanionActivationTransferID {
                return
            }

            lastHandledCompanionActivationTransferID = transferID
            let normalizedCode = OfflineActivation.normalizeActivationInput(code)

            do {
                try await applyActivationCode(normalizedCode)
                companionActivationFeedbackMessage = L10n.tr("activation.import.success")
            } catch {
                companionActivationFeedbackMessage = L10n.format(
                    "activation.import.failure",
                    error.localizedDescription
                )
            }
            #endif
        case .relayPairingToken(let token, let expiresAt):
            await consumeRelayPairingToken(token, expiresAt: expiresAt)
        default:
            break
        }
    }

    // MARK: - Private Helpers

    func updateRelayAccountStatus(
        _ status: RelayAccountStatusResponse?,
        shareToCompanion: Bool
    ) async {
        let previousStatus = relayAccountStatus
        relayAccountStatus = status

        guard shareToCompanion else {
            return
        }

        let previouslyActive = isManagedRelayAccessActive(for: previousStatus)
        let nowActive = isManagedRelayAccessActive(for: status)
        let keyChanged = previousStatus?.key?.keyValue != status?.key?.keyValue

        guard nowActive, previouslyActive == false || keyChanged else {
            return
        }

        await shareManagedRelayAccessToCompanionIfPossible()
    }

    private func isManagedRelayAccessActive(
        for status: RelayAccountStatusResponse?,
        now: Date = .now
    ) -> Bool {
        guard configuration.backendMode == .relay else {
            return false
        }

        guard let account = status?.account,
              let key = status?.key
        else {
            return false
        }

        if let expiresAt = account.creditExpiresAt, expiresAt <= now {
            return false
        }

        return account.state == .active && key.state == .active && account.creditBalance > 0
    }

    private func shareManagedRelayAccessToCompanionIfPossible() async {
        guard configuration.backendMode == .relay,
              configuration.relayBearerToken == nil,
              canTransferActivationCodeToPairedWatch,
              isManagedRelayAccessActive(for: relayAccountStatus)
        else {
            return
        }

        do {
            let pairingToken = try await relayAccountService.requestPairingToken()
            syncBridge.pushRelayPairingToken(pairingToken.pairingToken, expiresAt: pairingToken.expiresAt)
        } catch {
            companionActivationFeedbackMessage = "在线激活同步失败：\(error.localizedDescription)"
        }
    }

    private func consumeRelayPairingToken(_ token: String, expiresAt: Date?) async {
        guard configuration.backendMode == .relay else {
            return
        }

        if let expiresAt, expiresAt <= .now {
            return
        }

        do {
            let status = try await relayAccountService.joinPaired(pairingToken: token)
            await updateRelayAccountStatus(status, shareToCompanion: false)
            companionActivationFeedbackMessage = "已同步配对设备的在线激活。"
        } catch {
            companionActivationFeedbackMessage = "同步在线激活失败：\(error.localizedDescription)"
        }
    }

    func allowedModelsDescription(for allowedModelIDs: Set<String>?) -> String {
        guard let allowedModelIDs else {
            return L10n.tr("common.all")
        }

        let titles = LicensedModelCatalog.supportedModels
            .filter { allowedModelIDs.contains($0.id) }
            .map(\.title)

        return titles.isEmpty ? L10n.tr("common.all") : titles.joined(separator: L10n.tr("list.separator"))
    }

    private func relaySourceLabel(for source: RelayAccessSource) -> String {
        switch source {
        case .trial:
            return "试用"
        case .subscription:
            return "订阅"
        case .offlineManual:
            return "离线导入"
        }
    }

    #if canImport(StoreKit)
    private func verifiedStoreTransaction(
        from verificationResult: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch verificationResult {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }

    private func submittedTransaction(
        from transaction: Transaction,
        signedTransactionInfo: String?
    ) -> RelaySubmittedTransaction {
        RelaySubmittedTransaction(
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            environment: nil,
            signedTransactionInfo: signedTransactionInfo,
            signedRenewalInfo: nil,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revokedDate: transaction.revocationDate
        )
    }
    #endif
}
