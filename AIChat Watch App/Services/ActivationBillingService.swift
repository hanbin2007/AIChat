//
//  ActivationBillingService.swift
//  AIChat Watch App
//
//  Extracted from ChatStore — activation, licensing, and relay billing logic.
//

import Combine
import Foundation
import os
#if canImport(StoreKit)
import StoreKit
#endif

/// Typed outcomes raised by the relay billing flows so the UI can present an
/// honest message instead of a blanket "success".
enum RelayBillingOutcomeError: LocalizedError, Equatable {
    /// `restoreRelayPurchases` found no entitlements to submit, or the server
    /// accepted the restore but granted no usable managed access.
    case noRestorablePurchases

    var errorDescription: String? {
        switch self {
        case .noRestorablePurchases:
            return L10n.tr("relay.restore.no_grant")
        }
    }
}

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

    #if canImport(StoreKit)
    /// Long-lived listener for out-of-band StoreKit transaction updates
    /// (renewals, refunds, family-sharing revocations, Ask-to-Buy approvals).
    /// Without it those events never reach the relay and local/server access
    /// drift apart (H6).
    private var transactionUpdatesTask: Task<Void, Never>?
    #endif

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

        #if canImport(StoreKit)
        startTransactionUpdatesListener()
        #endif
    }

    deinit {
        #if canImport(StoreKit)
        transactionUpdatesTask?.cancel()
        #endif
    }

    #if canImport(StoreKit)
    /// Starts the `Transaction.updates` listener that forwards out-of-band
    /// renewals/refunds/revocations to the relay and finishes the transaction
    /// so StoreKit stops re-delivering it (H6).
    private func startTransactionUpdatesListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await verificationResult in Transaction.updates {
                if Task.isCancelled {
                    break
                }
                await self?.handleTransactionUpdate(verificationResult)
            }
        }
    }

    private func handleTransactionUpdate(
        _ verificationResult: VerificationResult<Transaction>
    ) async {
        guard case .verified(let transaction) = verificationResult else {
            // Unverified transactions can't be trusted for billing; leave them
            // unfinished so StoreKit re-delivers once it can verify them.
            return
        }

        do {
            let status = try await relayAccountService.submitPurchase(
                transaction: submittedTransaction(
                    from: transaction,
                    signedTransactionInfo: verificationResult.jwsRepresentation
                )
            )
            await updateRelayAccountStatus(status, shareToCompanion: true)
        } catch RelayAccountServiceError.unauthorized {
            await clearStoredRelayKeyAfterUnauthorized()
        } catch {
            // Best-effort: refresh local status so a refund/revocation that the
            // server already recorded is still reflected even if the submit
            // round-trip failed.
            relayBillingLog.error(
                "Relay transaction update submit failed: \(String(describing: error), privacy: .public)"
            )
            await refreshActivationState()
        }

        // Always finish so StoreKit stops replaying this update.
        await transaction.finish()
    }
    #endif

    // MARK: - Computed Properties

    var activationStatus: OfflineActivationStatus {
        OfflineActivation.status(for: activationState, deviceToken: deviceIdentity.deviceToken)
    }

    var relayAccessStatusTitle: String? {
        guard let account = relayAccountStatus?.account else {
            return nil
        }

        switch account.state {
        case .active:
            if let expiresAt = account.creditExpiresAt, expiresAt <= .now {
                return L10n.tr("relay.status.expired")
            }
            if account.creditBalance > 0 {
                return L10n.tr("relay.status.available")
            }
            return L10n.tr("relay.status.exhausted")
        case .paused:
            return L10n.tr("relay.status.paused")
        case .expired:
            return L10n.tr("relay.status.expired")
        case .inactive, .unknown:
            return L10n.tr("relay.status.inactive")
        }
    }

    var relayAccessStatusMessage: String? {
        guard let account = relayAccountStatus?.account else {
            return nil
        }

        var parts: [String] = []
        if let source = relayAccountStatus?.key?.source {
            parts.append(relaySourceLabel(for: source))
        }
        parts.append(L10n.format("relay.status.credits", account.creditBalance))

        if let expiration = account.creditExpiresAt {
            parts.append(
                L10n.format(
                    "relay.status.expires_at",
                    expiration.formatted(date: .abbreviated, time: .shortened)
                )
            )
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
        // The server account is the single source of truth for sending:
        // offline activation is only a stepping stone that must be exchanged
        // for managed relay access (see `applyActivationCode`). Without managed
        // access every send is blocked server-side — so the composer stays
        // read-only rather than pretending to be editable while
        // `activationFailureMessage` rejects each send (M1).
        hasManagedRelayAccess == false
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

        do {
            let status = try await relayAccountService.fetchAccountStatusIfPossible()
            if status != nil {
                await updateRelayAccountStatus(status, shareToCompanion: true)
            }
        } catch RelayAccountServiceError.unauthorized {
            // The stored rk_ key was revoked/expired server-side. Drop it so the
            // app stops presenting a dead credential and re-bootstraps cleanly
            // on the next access request (M2).
            await clearStoredRelayKeyAfterUnauthorized()
        } catch {
            // Other transient fetch errors are non-fatal: we keep any cached
            // status. The error is logged rather than silently dropped — the
            // previous comment claimed the caller propagated it, but nothing
            // did (L4).
            relayBillingLog.error(
                "Relay account status refresh failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Clears the locally stored relay key after the server reports the
    /// credential is no longer valid (HTTP 401), and resets the in-memory
    /// account status so the UI reflects the revoked state immediately (M2).
    private func clearStoredRelayKeyAfterUnauthorized() async {
        do {
            try await relayAccessRepository.clearStoredKey()
        } catch {
            relayBillingLog.error(
                "Failed to clear revoked relay key: \(String(describing: error), privacy: .public)"
            )
        }
        await updateRelayAccountStatus(nil, shareToCompanion: false)
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

        let status = try await relayAccountService.exchangeOfflineActivation(
            code: rawCode,
            state: nextState
        )
        await updateRelayAccountStatus(status, shareToCompanion: true)
    }

    func clearActivation() throws {
        try activationRepository.clearState()
        activationState = nil
    }

    func setActivationStateForPreview(_ state: OfflineActivationState?) {
        activationState = state
    }

    /// Synchronously seeds an account status into the published state for
    /// previews and tests. The relay-only app derives send access from managed
    /// relay status rather than offline activation, so preview/test stores that
    /// need an editable composer use this instead of applying an offline code.
    func setRelayAccountStatusForPreview(_ status: RelayAccountStatusResponse?) {
        relayAccountStatus = status
    }

    /// Seeds managed relay access for tests, persisting the status through the
    /// relay-access repository so a later `refreshActivationState()` (which
    /// reloads the cached status from disk) preserves it instead of wiping the
    /// in-memory seed. This mirrors how production code persists a fetched
    /// status before any refresh round-trip.
    func seedManagedRelayAccessForTesting(_ status: RelayAccountStatusResponse) async {
        try? await relayAccessRepository.saveStatus(status)
        relayAccountStatus = status
    }

    /// Builds an active managed-access status (active account + key + positive,
    /// non-expired credit balance) for previews and tests.
    static func previewManagedRelayAccessStatus(
        creditBalance: Int = 1_000,
        creditExpiresAt: Date? = nil
    ) -> RelayAccountStatusResponse {
        RelayAccountStatusResponse(
            account: RelayAccountSummary(
                accountID: UUID(),
                displayName: nil,
                adminNote: nil,
                state: .active,
                source: .subscription,
                planID: nil,
                originalTransactionID: nil,
                appAccountToken: nil,
                creditBalance: creditBalance,
                creditExpiresAt: creditExpiresAt,
                lastUsageAt: nil
            ),
            device: nil,
            key: RelayKeySummary(
                keyID: UUID(),
                keyValue: "preview-server-issued-key",
                state: .active,
                source: .subscription,
                note: nil,
                issuedAt: Date(timeIntervalSince1970: 0)
            ),
            grants: [],
            recentUsage: []
        )
    }

    func sendActivationCodeToPairedWatch(_ rawCode: String) {
        syncBridge.pushActivationCodeImport(rawCode)
    }

    func clearCompanionActivationFeedbackMessage() {
        companionActivationFeedbackMessage = nil
    }

    func refreshRelayCatalog() async throws {
        relayCatalog = try await relayAccountService.fetchCatalog()
    }

    @discardableResult
    func requestManagedRelayAccess() async throws -> RelayAccountStatusResponse? {
        let status = try await relayAccountService.refreshOrBootstrapStatus(forceBootstrap: true)
        await updateRelayAccountStatus(status, shareToCompanion: true)
        return status
    }

    @discardableResult
    func purchaseRelayPlan(id planID: String) async throws -> RelayStorePurchaseOutcome {
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

        // Nothing to restore: don't make the caller round-trip to the server
        // only to report a misleading "restore complete" with no grant (M8).
        guard submittedTransactions.isEmpty == false else {
            throw RelayBillingOutcomeError.noRestorablePurchases
        }

        let status = try await relayAccountService.restorePurchases(transactions: submittedTransactions)
        await updateRelayAccountStatus(status, shareToCompanion: true)

        // The server accepted the restore but granted nothing usable (no active
        // managed access). Surface a real failure instead of swallowing it and
        // telling the user the restore succeeded (M8).
        guard isManagedRelayAccessActive(for: status) else {
            throw RelayBillingOutcomeError.noRestorablePurchases
        }

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
        if hasManagedRelayAccess {
            return nil
        }

        guard let account = relayAccountStatus?.account else {
            // No managed access and no online account yet: the device needs
            // to bind online. Surface an actionable CTA instead of a
            // permanent "verifying…" message that never resolves (M1).
            return L10n.tr("relay.access.needs_online_binding")
        }

        switch account.state {
        case .active:
            if let expiresAt = account.creditExpiresAt, expiresAt <= .now {
                return L10n.tr("relay.failure.credits_expired")
            }
            return account.creditBalance > 0 ? nil : L10n.tr("relay.failure.credits_exhausted")
        case .paused:
            return L10n.tr("relay.failure.key_paused")
        case .expired:
            return L10n.tr("relay.failure.credits_expired")
        case .inactive, .unknown:
            return L10n.tr("relay.failure.device_inactive")
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

    /// Reverses a single offline-credit consumption when the send it paid for
    /// failed or was cancelled before completing. Managed relay access is
    /// metered server-side per completed request, so there is nothing to refund
    /// in that mode (M6).
    func refundActivationMessage() {
        guard hasManagedRelayAccess == false else {
            return
        }

        guard let currentState = activationState,
              currentState.usedMessageCount > 0
        else {
            return
        }

        var refundedState = currentState
        refundedState.usedMessageCount -= 1

        do {
            try activationRepository.saveState(refundedState)
            activationState = refundedState
        } catch {
            relayBillingLog.error(
                "Failed to refund offline activation credit: \(String(describing: error), privacy: .public)"
            )
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
        guard let account = status?.account,
              let key = status?.key
        else {
            return false
        }

        guard key.keyValue.nonEmptyTrimmed != nil else {
            return false
        }

        if let expiresAt = account.creditExpiresAt, expiresAt <= now {
            return false
        }

        return account.state == .active && key.state == .active && account.creditBalance > 0
    }

    private func shareManagedRelayAccessToCompanionIfPossible() async {
        guard configuration.relayBearerToken == nil,
              canTransferActivationCodeToPairedWatch,
              isManagedRelayAccessActive(for: relayAccountStatus)
        else {
            return
        }

        do {
            let pairingToken = try await relayAccountService.requestPairingToken()
            syncBridge.pushRelayPairingToken(pairingToken.pairingToken, expiresAt: pairingToken.expiresAt)
        } catch {
            companionActivationFeedbackMessage = L10n.format(
                "relay.sync.share_failed",
                error.localizedDescription
            )
        }
    }

    private func consumeRelayPairingToken(_ token: String, expiresAt: Date?) async {
        if let expiresAt, expiresAt <= .now {
            return
        }

        do {
            let status = try await relayAccountService.joinPaired(pairingToken: token)
            await updateRelayAccountStatus(status, shareToCompanion: false)
            companionActivationFeedbackMessage = L10n.tr("relay.sync.joined")
        } catch {
            companionActivationFeedbackMessage = L10n.format(
                "relay.sync.join_failed",
                error.localizedDescription
            )
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
            return L10n.tr("relay.source.trial")
        case .subscription:
            return L10n.tr("relay.source.subscription")
        case .offlineManual:
            return L10n.tr("relay.source.offline")
        case .unknown:
            return L10n.tr("relay.source.subscription")
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
