import Foundation

private enum RelayBillingStoreConstants {
    static let stateFilename = "relay-billing-state.json"
    static let pairingTokenLifetime: TimeInterval = 10 * 60
    static let recentUsageLimit = 24
}

struct RelayBillingSnapshot: Sendable {
    var accounts: [RelayAccountSummary]
    var devices: [RelayDeviceSummary]
    var keys: [RelayKeySummary]
    var grants: [RelayGrantSummary]
    var usage: [RelayUsageSummary]
    var plans: [RelayPlanCatalogItem]
    var meteringPolicy: RelayMeteringPolicySnapshot
}

struct RelayAuthorizedKeyContext: Sendable {
    var accountID: UUID
    var deviceID: String
    var keyID: UUID
    var source: RelayAccessSource
}

actor RelayBillingStore {
    static let defaultPolicy = RelayBillingState.makeDefault().meteringPolicy
    static let defaultPlans = RelayBillingState.makeDefault().plans

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var state: RelayBillingState

    init(fileURL: URL? = nil) {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.fileURL = fileURL ?? Self.defaultFileURL()
        var resolvedState = RelayBillingState.makeDefault()
        resolvedState.compact(now: .now)
        if let persistedState = Self.loadPersistedStateIfAvailable(
            from: self.fileURL,
            using: self.decoder
        ) {
            resolvedState = persistedState
        }
        resolvedState.compact(now: .now)
        self.state = resolvedState
    }

    func snapshot() -> RelayBillingSnapshot {
        state.compact(now: .now)
        return RelayBillingSnapshot(
            accounts: state.accounts.values.map(\.summary).sorted { lhs, rhs in
                lhs.lastUsageAt ?? .distantPast > rhs.lastUsageAt ?? .distantPast
            },
            devices: state.devices.values.map(\.summary).sorted { lhs, rhs in
                lhs.lastSeenAt ?? .distantPast > rhs.lastSeenAt ?? .distantPast
            },
            keys: state.keys.values.map(\.summary).sorted { $0.issuedAt > $1.issuedAt },
            grants: state.grants.values.map(\.summary).sorted { $0.grantedAt > $1.grantedAt },
            usage: state.usage.sorted(by: { $0.createdAt > $1.createdAt }).prefix(200).map(\.summary),
            plans: state.plans,
            meteringPolicy: state.meteringPolicy
        )
    }

    func catalogResponse() -> RelayCatalogResponse {
        RelayCatalogResponse(
            plans: state.plans,
            meteringPolicy: state.meteringPolicy
        )
    }

    func bootstrap(request: RelayActivationBootstrapRequest) async throws -> RelayAccountStatusResponse {
        state.compact(now: .now)

        if var existingDevice = state.devices[request.deviceID],
           let account = state.accounts[existingDevice.accountID] {
            existingDevice.touch(now: .now)
            state.devices[request.deviceID] = existingDevice
            if let keyID = existingDevice.keyID,
               let existingKey = state.keys[keyID],
               existingKey.state == .active {
                try persist()
                return statusResponse(accountID: account.id, deviceID: request.deviceID)
            }
        }

        guard state.trialClaims[request.deviceID] == nil else {
            return RelayAccountStatusResponse(
                account: nil,
                device: RelayDeviceSummary(
                    deviceID: request.deviceID,
                    platform: request.platform,
                    alias: request.deviceAlias,
                    note: nil,
                    keyID: nil,
                    lastSeenAt: .now
                ),
                key: nil,
                grants: [],
                recentUsage: []
            )
        }

        let accountID = UUID()
        let keyID = UUID()
        let grantID = UUID()
        let now = Date.now
        let expiration = Calendar.current.date(byAdding: .day, value: state.meteringPolicy.trialDurationDays, to: now)
        let keyValue = Self.generateClientKey()

        var account = RelayBillingAccountRecord(
            id: accountID,
            displayName: request.deviceAlias,
            adminNote: nil,
            state: .active,
            source: .trial,
            planID: nil,
            originalTransactionID: nil,
            appAccountToken: UUID(),
            deviceIDs: [request.deviceID],
            keyIDs: [keyID],
            grantIDs: [grantID],
            lastUsageAt: nil
        )
        account.recalculateBalance(grants: state.grants)

        let device = RelayBillingDeviceRecord(
            deviceID: request.deviceID,
            accountID: accountID,
            platform: request.platform,
            alias: request.deviceAlias,
            note: nil,
            keyID: keyID,
            lastSeenAt: now
        )

        let key = RelayBillingKeyRecord(
            id: keyID,
            accountID: accountID,
            deviceID: request.deviceID,
            keyValue: keyValue,
            state: .active,
            source: .trial,
            note: nil,
            issuedAt: now
        )

        let grant = RelayBillingGrantRecord(
            id: grantID,
            accountID: accountID,
            source: .trial,
            totalCredits: state.meteringPolicy.trialCredits,
            remainingCredits: state.meteringPolicy.trialCredits,
            grantedAt: now,
            expiresAt: expiration,
            sourceTransactionID: nil,
            note: "Auto-issued trial grant"
        )

        state.accounts[accountID] = account
        state.devices[request.deviceID] = device
        state.keys[keyID] = key
        state.grants[grantID] = grant
        state.trialClaims[request.deviceID] = RelayBillingTrialClaimRecord(
            deviceID: request.deviceID,
            grantID: grantID,
            claimedAt: now
        )
        refreshAccountBalance(for: accountID)
        try persist()
        return statusResponse(accountID: accountID, deviceID: request.deviceID)
    }

    func purchasePrepare(
        request: RelayPurchasePrepareRequest,
        currentKey: String?
    ) async throws -> RelayPurchasePrepareResponse {
        state.compact(now: .now)

        if let currentKey,
           let existingKey = state.keyRecord(for: currentKey),
           let account = state.accounts[existingKey.accountID] {
            let token = account.appAccountToken ?? UUID()
            if account.appAccountToken == nil {
                var updated = account
                updated.appAccountToken = token
                state.accounts[updated.id] = updated
                try persist()
            }
            return RelayPurchasePrepareResponse(
                accountID: account.id,
                appAccountToken: token
            )
        }

        if let device = state.devices[request.deviceID],
           let account = state.accounts[device.accountID] {
            let token = account.appAccountToken ?? UUID()
            if account.appAccountToken == nil {
                var updated = account
                updated.appAccountToken = token
                state.accounts[updated.id] = updated
                try persist()
            }
            return RelayPurchasePrepareResponse(accountID: account.id, appAccountToken: token)
        }

        let accountID = UUID()
        let token = UUID()
        let account = RelayBillingAccountRecord(
            id: accountID,
            displayName: request.deviceID,
            adminNote: nil,
            state: .inactive,
            source: .subscription,
            planID: nil,
            originalTransactionID: nil,
            appAccountToken: token,
            deviceIDs: [],
            keyIDs: [],
            grantIDs: [],
            lastUsageAt: nil
        )
        state.accounts[accountID] = account
        try persist()
        return RelayPurchasePrepareResponse(accountID: accountID, appAccountToken: token)
    }

    func submitPurchase(_ request: RelayPurchaseSubmitRequest) async throws -> RelayPurchaseSubmissionResponse {
        let normalizedTransaction = try normalizedSubmittedTransaction(request.transaction)
        let accountID = try resolvePurchasingAccountID(
            preferredDeviceID: request.deviceID,
            platform: request.platform,
            transaction: normalizedTransaction
        )

        if let existingTransaction = state.transactions[normalizedTransaction.transaction.transactionID] {
            state.transactions[normalizedTransaction.transaction.transactionID] = normalizedTransaction.transaction
            try reconcileStoredTransaction(
                normalizedTransaction,
                previousTransaction: existingTransaction,
                accountID: accountID,
                preferredDeviceID: request.deviceID,
                platform: request.platform
            )
        } else {
            state.transactions[normalizedTransaction.transaction.transactionID] = normalizedTransaction.transaction
            try applyTransaction(
                normalizedTransaction,
                to: accountID,
                preferredDeviceID: request.deviceID,
                platform: request.platform
            )
        }

        try persist()
        return RelayPurchaseSubmissionResponse(
            status: statusResponse(accountID: accountID, deviceID: request.deviceID)
        )
    }

    func restorePurchases(_ request: RelayRestorePurchasesRequest) async throws -> RelayPurchaseSubmissionResponse {
        var resolvedAccountID: UUID?

        for submittedTransaction in request.transactions {
            let normalizedTransaction = try normalizedSubmittedTransaction(submittedTransaction)
            let accountID = try resolvePurchasingAccountID(
                preferredDeviceID: request.deviceID,
                platform: request.platform,
                transaction: normalizedTransaction
            )
            resolvedAccountID = accountID

            if let existingTransaction = state.transactions[normalizedTransaction.transaction.transactionID] {
                state.transactions[normalizedTransaction.transaction.transactionID] = normalizedTransaction.transaction
                try reconcileStoredTransaction(
                    normalizedTransaction,
                    previousTransaction: existingTransaction,
                    accountID: accountID,
                    preferredDeviceID: request.deviceID,
                    platform: request.platform
                )
            } else {
                state.transactions[normalizedTransaction.transaction.transactionID] = normalizedTransaction.transaction
                try applyTransaction(
                    normalizedTransaction,
                    to: accountID,
                    preferredDeviceID: request.deviceID,
                    platform: request.platform
                )
            }
        }

        let accountID: UUID
        if let resolvedAccountID {
            accountID = resolvedAccountID
        } else {
            accountID = try ensurePurchasingAccount(
                deviceID: request.deviceID,
                platform: request.platform
            )
        }
        _ = try ensureKey(
            accountID: accountID,
            deviceID: request.deviceID,
            platform: request.platform,
            source: .subscription
        )

        try persist()
        return RelayPurchaseSubmissionResponse(
            status: statusResponse(accountID: accountID, deviceID: request.deviceID)
        )
    }

    func pairingToken(forClientKey clientKey: String) async throws -> RelayPairingTokenResponse {
        guard let key = state.keyRecord(for: clientKey),
              key.state == .active
        else {
            throw RelayHTTPError.unauthorized
        }

        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let expiresAt = Date.now.addingTimeInterval(RelayBillingStoreConstants.pairingTokenLifetime)
        state.pairingTokens[value] = RelayPairingTokenRecord(
            token: value,
            accountID: key.accountID,
            createdByDeviceID: key.deviceID,
            expiresAt: expiresAt
        )
        try persist()
        return RelayPairingTokenResponse(pairingToken: value, expiresAt: expiresAt)
    }

    func joinPaired(_ request: RelayJoinPairedRequest) async throws -> RelayAccountStatusResponse {
        state.compact(now: .now)
        guard let token = state.pairingTokens[request.pairingToken],
              token.expiresAt > .now
        else {
            throw RelayHTTPError.badRequest("Pairing token is invalid or expired.")
        }

        let accountID = token.accountID
        guard var account = state.accounts[accountID] else {
            throw RelayHTTPError.badRequest("Account not found.")
        }

        let boundDeviceIDs = Set(account.deviceIDs)
        if boundDeviceIDs.contains(request.deviceID) == false,
           boundDeviceIDs.count >= max(1, state.meteringPolicy.maxBoundDevices) {
            throw RelayHTTPError.badRequest("Reached the maximum number of bound devices.")
        }

        _ = try ensureKey(
            accountID: accountID,
            deviceID: request.deviceID,
            platform: request.platform,
            source: account.source,
            deviceAlias: request.deviceAlias
        )

        account.deviceIDs = Array(Set(account.deviceIDs + [request.deviceID])).sorted()
        state.accounts[accountID] = account
        state.pairingTokens.removeValue(forKey: request.pairingToken)
        try persist()
        return statusResponse(accountID: accountID, deviceID: request.deviceID)
    }

    func accountStatus(clientKey: String?, deviceID: String?) async -> RelayAccountStatusResponse {
        state.compact(now: .now)

        if let clientKey,
           let key = state.keyRecord(for: clientKey) {
            return statusResponse(accountID: key.accountID, deviceID: key.deviceID)
        }

        if let deviceID,
           let device = state.devices[deviceID] {
            return statusResponse(accountID: device.accountID, deviceID: deviceID)
        }

        return RelayAccountStatusResponse(account: nil, device: nil, key: nil, grants: [], recentUsage: [])
    }

    func exchangeOffline(_ request: RelayOfflineExchangeRequest) async throws -> RelayAccountStatusResponse {
        state.compact(now: .now)
        if let existingDevice = state.devices[request.deviceID],
           let existingAccount = state.accounts[existingDevice.accountID],
           existingAccount.source == .subscription {
            return statusResponse(accountID: existingAccount.id, deviceID: request.deviceID)
        }

        let accountID: UUID
        let grantID = UUID()
        let totalCredits = max(0, request.creditsTotal ?? state.meteringPolicy.trialCredits)
        let remainingCredits = request.creditsRemaining.map { max(0, min(totalCredits, $0)) } ?? totalCredits
        let normalizedAllowedModels = request.allowedModelIDs?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let grantNoteComponents = [
            "Imported from offline activation",
            request.activationFingerprint?.nonEmptyTrimmed.map { "Fingerprint: \($0)" },
            normalizedAllowedModels?.isEmpty == false ? "Models: \(normalizedAllowedModels!.joined(separator: ", "))" : nil
        ]
        .compactMap { $0 }
        if let existingDevice = state.devices[request.deviceID],
           var existingAccount = state.accounts[existingDevice.accountID] {
            accountID = existingAccount.id
            for existingGrantID in existingAccount.grantIDs {
                guard var existingGrant = state.grants[existingGrantID],
                      existingGrant.source != .subscription
                else {
                    continue
                }
                existingGrant.remainingCredits = 0
                state.grants[existingGrantID] = existingGrant
            }

            let key = try ensureKey(
                accountID: accountID,
                deviceID: request.deviceID,
                platform: request.platform,
                source: .offlineManual,
                deviceAlias: request.deviceAlias
            )

            existingAccount.displayName = request.deviceAlias?.nonEmptyTrimmed ?? existingAccount.displayName
            existingAccount.state = .active
            existingAccount.source = .offlineManual
            existingAccount.appAccountToken = existingAccount.appAccountToken ?? UUID()
            existingAccount.grantIDs = Array(Set(existingAccount.grantIDs + [grantID])).sorted { $0.uuidString < $1.uuidString }
            existingAccount.keyIDs = Array(Set(existingAccount.keyIDs + [key.id])).sorted { $0.uuidString < $1.uuidString }
            state.accounts[accountID] = existingAccount

            if var keyRecord = state.keys[key.id] {
                keyRecord.source = .offlineManual
                state.keys[key.id] = keyRecord
            }
        } else {
            accountID = UUID()
            let key = RelayBillingKeyRecord(
                id: UUID(),
                accountID: accountID,
                deviceID: request.deviceID,
                keyValue: Self.generateClientKey(),
                state: .active,
                source: .offlineManual,
                note: nil,
                issuedAt: .now
            )

            let device = RelayBillingDeviceRecord(
                deviceID: request.deviceID,
                accountID: accountID,
                platform: request.platform,
                alias: request.deviceAlias,
                note: nil,
                keyID: key.id,
                lastSeenAt: .now
            )

            let account = RelayBillingAccountRecord(
                id: accountID,
                displayName: request.deviceAlias,
                adminNote: nil,
                state: .active,
                source: .offlineManual,
                planID: nil,
                originalTransactionID: nil,
                appAccountToken: UUID(),
                deviceIDs: [request.deviceID],
                keyIDs: [key.id],
                grantIDs: [grantID],
                lastUsageAt: nil
            )

            state.accounts[accountID] = account
            state.devices[request.deviceID] = device
            state.keys[key.id] = key
        }

        state.grants[grantID] = RelayBillingGrantRecord(
            id: grantID,
            accountID: accountID,
            source: .offlineManual,
            totalCredits: totalCredits,
            remainingCredits: remainingCredits,
            grantedAt: .now,
            expiresAt: request.validUntil,
            sourceTransactionID: nil,
            note: grantNoteComponents.joined(separator: "\n")
        )
        refreshAccountBalance(for: accountID)
        try persist()
        return statusResponse(accountID: accountID, deviceID: request.deviceID)
    }

    func authorize(clientKey: String) async -> RelayAuthorizedKeyContext? {
        state.compact(now: .now)
        guard let key = state.keyRecord(for: clientKey),
              key.state == .active,
              let account = state.accounts[key.accountID],
              account.state == .active,
              account.creditBalance > 0
        else {
            return nil
        }

        state.devices[key.deviceID]?.touch(now: .now)
        return RelayAuthorizedKeyContext(
            accountID: key.accountID,
            deviceID: key.deviceID,
            keyID: key.id,
            source: key.source
        )
    }

    func modifyAccount(
        accountID: UUID,
        displayName: String?,
        adminNote: String?,
        state nextState: RelayAccountState?,
        planID: String?
    ) async throws {
        guard var account = state.accounts[accountID] else {
            throw RelayHTTPError.badRequest("Account not found.")
        }

        account.displayName = displayName?.nonEmptyTrimmed
        account.adminNote = adminNote?.nonEmptyTrimmed
        if let nextState {
            account.state = nextState
        }
        if let planID {
            account.planID = planID.nonEmptyTrimmed
        }
        state.accounts[accountID] = account
        try persist()
    }

    func modifyDevice(deviceID: String, alias: String?, note: String?) async throws {
        guard var device = state.devices[deviceID] else {
            throw RelayHTTPError.badRequest("Device not found.")
        }

        device.alias = alias?.nonEmptyTrimmed
        device.note = note?.nonEmptyTrimmed
        state.devices[deviceID] = device
        try persist()
    }

    func modifyKey(keyID: UUID, state nextState: RelayKeyState?, note: String?) async throws {
        guard var key = state.keys[keyID] else {
            throw RelayHTTPError.badRequest("Key not found.")
        }

        if let nextState {
            key.state = nextState
        }
        key.note = note?.nonEmptyTrimmed
        state.keys[keyID] = key
        try persist()
    }

    func modifyGrant(grantID: UUID, remainingCredits: Int?, note: String?) async throws {
        guard var grant = state.grants[grantID] else {
            throw RelayHTTPError.badRequest("Grant not found.")
        }

        if let remainingCredits {
            grant.remainingCredits = max(0, min(grant.totalCredits, remainingCredits))
        }
        if let note {
            grant.note = note.nonEmptyTrimmed
        }
        state.grants[grantID] = grant
        refreshAccountBalance(for: grant.accountID)
        try persist()
    }

    func grantCredits(
        accountID: UUID,
        credits: Int,
        source: RelayAccessSource,
        expiresAt: Date?,
        note: String?
    ) async throws {
        guard state.accounts[accountID] != nil else {
            throw RelayHTTPError.badRequest("Account not found.")
        }

        let grant = RelayBillingGrantRecord(
            id: UUID(),
            accountID: accountID,
            source: source,
            totalCredits: max(0, credits),
            remainingCredits: max(0, credits),
            grantedAt: .now,
            expiresAt: expiresAt,
            sourceTransactionID: nil,
            note: note?.nonEmptyTrimmed
        )
        state.grants[grant.id] = grant
        state.accounts[accountID]?.grantIDs.append(grant.id)
        refreshAccountBalance(for: accountID)
        try persist()
    }

    func updateMeteringPolicy(_ policy: RelayMeteringPolicySnapshot, plans: [RelayPlanCatalogItem]) async throws {
        state.meteringPolicy = policy
        state.plans = plans
        try persist()
    }

    func recordUsage(
        accountID: UUID,
        deviceID: String,
        keyID: UUID,
        endpoint: String,
        modelID: String,
        inputTokens: Int,
        outputTokens: Int,
        searchCount: Int,
        reservedCredits: Int,
        settledCredits: Int
    ) async throws {
        try deductCredits(from: accountID, amount: settledCredits)

        let entry = RelayBillingUsageRecord(
            requestID: UUID(),
            accountID: accountID,
            deviceID: deviceID,
            keyID: keyID,
            endpoint: endpoint,
            modelID: modelID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            reservedCredits: reservedCredits,
            settledCredits: settledCredits,
            searchCount: searchCount,
            createdAt: .now
        )
        state.usage.append(entry)
        state.accounts[accountID]?.lastUsageAt = entry.createdAt
        state.devices[deviceID]?.lastSeenAt = entry.createdAt
        refreshAccountBalance(for: accountID)
        try persist()
    }

    func ensureCreditAllowance(accountID: UUID, requiredCredits: Int) async throws {
        state.compact(now: .now)
        guard let account = state.accounts[accountID] else {
            throw RelayHTTPError.badRequest("Account not found.")
        }

        guard account.state == .active else {
            throw RelayHTTPError.paymentRequired("Account is not active.")
        }

        guard requiredCredits > 0 else {
            return
        }

        guard account.creditBalance >= requiredCredits else {
            throw RelayHTTPError.paymentRequired(
                "Insufficient credits. Required \(requiredCredits), available \(account.creditBalance)."
            )
        }
    }

    func creditsForUsage(
        modelID: String,
        inputTokens: Int,
        outputTokens: Int,
        searchCount: Int,
        inputTokensOver200k: Bool,
        usesAudioInput: Bool
    ) -> Int {
        guard let rate = state.meteringPolicy.rates.first(where: { $0.modelID == modelID }) else {
            return 0
        }

        let multiplier = NSDecimalNumber(decimal: state.meteringPolicy.creditMultiplier).doubleValue
        let inputRate: Int
        if usesAudioInput, let audioRate = rate.audioInputCreditsPerMillion {
            inputRate = audioRate
        } else {
            inputRate = inputTokensOver200k
                ? (rate.inputCreditsPerMillionOver200k ?? rate.inputCreditsPerMillion)
                : rate.inputCreditsPerMillion
        }
        let outputRate = inputTokensOver200k ? (rate.outputCreditsPerMillionOver200k ?? rate.outputCreditsPerMillion) : rate.outputCreditsPerMillion
        let searchCredits = rate.searchSurchargeCredits * max(0, searchCount)
        let baseCredits =
            (Double(inputTokens) / 1_000_000.0) * Double(inputRate) +
            (Double(outputTokens) / 1_000_000.0) * Double(outputRate) +
            Double(searchCredits)
        return max(1, Int(ceil(baseCredits * multiplier)))
    }

    private func ensurePurchasingAccount(deviceID: String, platform: RelayDevicePlatform) throws -> UUID {
        if let device = state.devices[deviceID] {
            return device.accountID
        }

        let accountID = UUID()
        let account = RelayBillingAccountRecord(
            id: accountID,
            displayName: deviceID,
            adminNote: nil,
            state: .inactive,
            source: .subscription,
            planID: nil,
            originalTransactionID: nil,
            appAccountToken: UUID(),
            deviceIDs: [deviceID],
            keyIDs: [],
            grantIDs: [],
            lastUsageAt: nil
        )
        let device = RelayBillingDeviceRecord(
            deviceID: deviceID,
            accountID: accountID,
            platform: platform,
            alias: nil,
            note: nil,
            keyID: nil,
            lastSeenAt: .now
        )
        state.accounts[accountID] = account
        state.devices[deviceID] = device
        return accountID
    }

    private func resolvePurchasingAccountID(
        preferredDeviceID: String,
        platform: RelayDevicePlatform,
        transaction: RelayNormalizedSubmittedTransaction
    ) throws -> UUID {
        if let appAccountToken = transaction.appAccountToken,
           let account = state.accounts.values.first(where: { $0.appAccountToken == appAccountToken }) {
            return account.id
        }

        let originalTransactionID = transaction.transaction.originalTransactionID ?? transaction.transaction.transactionID
        if let account = state.accounts.values.first(where: { $0.originalTransactionID == originalTransactionID }) {
            return account.id
        }

        let accountID = try ensurePurchasingAccount(
            deviceID: preferredDeviceID,
            platform: platform
        )
        if let appAccountToken = transaction.appAccountToken,
           var account = state.accounts[accountID],
           account.appAccountToken == nil {
            account.appAccountToken = appAccountToken
            state.accounts[accountID] = account
        }
        return accountID
    }

    private func applyTransaction(
        _ normalizedTransaction: RelayNormalizedSubmittedTransaction,
        to accountID: UUID,
        preferredDeviceID: String,
        platform: RelayDevicePlatform
    ) throws {
        let transaction = normalizedTransaction.transaction
        guard let plan = state.plans.first(where: { $0.productID == transaction.productID }) else {
            throw RelayHTTPError.badRequest("Unknown product id: \(transaction.productID)")
        }

        let grantID = UUID()
        let expiration = transaction.expirationDate
            .flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        let grant = RelayBillingGrantRecord(
            id: grantID,
            accountID: accountID,
            source: .subscription,
            totalCredits: plan.monthlyCredits,
            remainingCredits: plan.monthlyCredits,
            grantedAt: transaction.purchaseDate ?? .now,
            expiresAt: expiration,
            sourceTransactionID: transaction.transactionID,
            note: "Granted from \(transaction.productID)"
        )
        state.grants[grantID] = grant

        guard var account = state.accounts[accountID] else {
            throw RelayHTTPError.badRequest("Account not found.")
        }
        account.state = transaction.revokedDate == nil ? .active : .paused
        account.source = .subscription
        account.planID = plan.id
        account.originalTransactionID = transaction.originalTransactionID ?? transaction.transactionID
        if let appAccountToken = normalizedTransaction.appAccountToken {
            if let existingToken = account.appAccountToken,
               existingToken != appAccountToken {
                throw RelayHTTPError.badRequest("App account token mismatch.")
            }
            account.appAccountToken = appAccountToken
        } else {
            account.appAccountToken = account.appAccountToken ?? UUID()
        }
        account.grantIDs.append(grantID)
        if account.deviceIDs.contains(preferredDeviceID) == false {
            account.deviceIDs.append(preferredDeviceID)
        }
        state.accounts[accountID] = account

        _ = try ensureKey(
            accountID: accountID,
            deviceID: preferredDeviceID,
            platform: platform,
            source: .subscription
        )
        refreshAccountBalance(for: accountID)
    }

    private func reconcileStoredTransaction(
        _ normalizedTransaction: RelayNormalizedSubmittedTransaction,
        previousTransaction: RelaySubmittedTransaction,
        accountID: UUID,
        preferredDeviceID: String,
        platform: RelayDevicePlatform
    ) throws {
        let transaction = normalizedTransaction.transaction
        guard let plan = state.plans.first(where: { $0.productID == transaction.productID }) else {
            throw RelayHTTPError.badRequest("Unknown product id: \(transaction.productID)")
        }

        guard var account = state.accounts[accountID] else {
            throw RelayHTTPError.badRequest("Account not found.")
        }

        account.state = transaction.revokedDate == nil ? .active : .paused
        account.source = .subscription
        account.planID = plan.id
        account.originalTransactionID = transaction.originalTransactionID ?? transaction.transactionID
        if let appAccountToken = normalizedTransaction.appAccountToken {
            if let existingToken = account.appAccountToken,
               existingToken != appAccountToken {
                throw RelayHTTPError.badRequest("App account token mismatch.")
            }
            account.appAccountToken = appAccountToken
        } else {
            account.appAccountToken = account.appAccountToken ?? UUID()
        }
        if account.deviceIDs.contains(preferredDeviceID) == false {
            account.deviceIDs.append(preferredDeviceID)
        }
        state.accounts[accountID] = account

        let expiration = transaction.expirationDate
            .flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        var foundGrant = false
        for grantID in account.grantIDs {
            guard var grant = state.grants[grantID],
                  grant.source == .subscription,
                  grant.sourceTransactionID == transaction.transactionID
            else {
                continue
            }

            foundGrant = true
            grant.expiresAt = expiration
            if let revokedDate = transaction.revokedDate {
                grant.remainingCredits = 0
                grant.note = [grant.note, "Revoked at \(revokedDate.formatted(date: .abbreviated, time: .shortened))"]
                    .compactMap { $0?.nonEmptyTrimmed }
                    .joined(separator: "\n")
            } else if previousTransaction.revokedDate != nil && grant.remainingCredits == 0 {
                grant.remainingCredits = grant.totalCredits
            }
            state.grants[grantID] = grant
        }

        if foundGrant == false && transaction.revokedDate == nil {
            try applyTransaction(
                normalizedTransaction,
                to: accountID,
                preferredDeviceID: preferredDeviceID,
                platform: platform
            )
            return
        }

        _ = try ensureKey(
            accountID: accountID,
            deviceID: preferredDeviceID,
            platform: platform,
            source: .subscription
        )
        refreshAccountBalance(for: accountID)
    }

    private func normalizedSubmittedTransaction(
        _ transaction: RelaySubmittedTransaction
    ) throws -> RelayNormalizedSubmittedTransaction {
        guard let signedTransactionInfo = transaction.signedTransactionInfo?.nonEmptyTrimmed else {
            throw RelayHTTPError.badRequest("Missing signed transaction info.")
        }

        let payload = try RelayAppStoreTransactionPayload.decode(fromJWS: signedTransactionInfo)

        if transaction.transactionID.isEmpty == false,
           transaction.transactionID != payload.transactionID {
            throw RelayHTTPError.badRequest("Transaction id mismatch.")
        }

        if transaction.productID.isEmpty == false,
           transaction.productID != payload.productID {
            throw RelayHTTPError.badRequest("Product id mismatch.")
        }

        if let originalTransactionID = transaction.originalTransactionID?.nonEmptyTrimmed,
           let payloadOriginalTransactionID = payload.originalTransactionID?.nonEmptyTrimmed,
           originalTransactionID != payloadOriginalTransactionID {
            throw RelayHTTPError.badRequest("Original transaction id mismatch.")
        }

        if let environment = transaction.environment?.nonEmptyTrimmed?.lowercased(),
           let payloadEnvironment = payload.environment?.nonEmptyTrimmed?.lowercased(),
           environment != payloadEnvironment {
            throw RelayHTTPError.badRequest("Environment mismatch.")
        }

        return RelayNormalizedSubmittedTransaction(
            transaction: RelaySubmittedTransaction(
                transactionID: payload.transactionID,
                originalTransactionID: payload.originalTransactionID ?? transaction.originalTransactionID,
                productID: payload.productID,
                environment: payload.environment ?? transaction.environment,
                signedTransactionInfo: signedTransactionInfo,
                signedRenewalInfo: transaction.signedRenewalInfo,
                purchaseDate: payload.purchaseDate ?? transaction.purchaseDate,
                expirationDate: payload.expirationDate ?? transaction.expirationDate,
                revokedDate: payload.revocationDate ?? transaction.revokedDate
            ),
            appAccountToken: payload.appAccountToken
        )
    }

    @discardableResult
    private func ensureKey(
        accountID: UUID,
        deviceID: String,
        platform: RelayDevicePlatform,
        source: RelayAccessSource,
        deviceAlias: String? = nil
    ) throws -> RelayBillingKeyRecord {
        if let device = state.devices[deviceID],
           device.accountID == accountID,
           let keyID = device.keyID,
           var existingKey = state.keys[keyID] {
            if let deviceAlias {
                state.devices[deviceID]?.alias = deviceAlias.nonEmptyTrimmed
            }
            existingKey.source = source
            state.keys[keyID] = existingKey
            return existingKey
        }

        if let existingDevice = state.devices[deviceID],
           existingDevice.accountID != accountID {
            detachDevice(deviceID)
        }

        let key = RelayBillingKeyRecord(
            id: UUID(),
            accountID: accountID,
            deviceID: deviceID,
            keyValue: Self.generateClientKey(),
            state: .active,
            source: source,
            note: nil,
            issuedAt: .now
        )
        state.keys[key.id] = key

        let device = RelayBillingDeviceRecord(
            deviceID: deviceID,
            accountID: accountID,
            platform: platform,
            alias: deviceAlias,
            note: nil,
            keyID: key.id,
            lastSeenAt: .now
        )
        state.devices[deviceID] = device
        state.accounts[accountID]?.deviceIDs = Array(Set((state.accounts[accountID]?.deviceIDs ?? []) + [deviceID])).sorted()
        state.accounts[accountID]?.keyIDs = Array(Set((state.accounts[accountID]?.keyIDs ?? []) + [key.id])).sorted { $0.uuidString < $1.uuidString }
        return key
    }

    private func detachDevice(_ deviceID: String) {
        guard let existingDevice = state.devices.removeValue(forKey: deviceID) else {
            return
        }

        if let oldKeyID = existingDevice.keyID {
            state.keys.removeValue(forKey: oldKeyID)
        }

        guard var oldAccount = state.accounts[existingDevice.accountID] else {
            return
        }

        oldAccount.deviceIDs.removeAll { $0 == deviceID }
        if let oldKeyID = existingDevice.keyID {
            oldAccount.keyIDs.removeAll { $0 == oldKeyID }
        }
        if oldAccount.deviceIDs.isEmpty && oldAccount.keyIDs.isEmpty {
            oldAccount.state = .inactive
        }
        oldAccount.recalculateBalance(grants: state.grants)
        state.accounts[oldAccount.id] = oldAccount
    }

    private func deductCredits(from accountID: UUID, amount: Int) throws {
        guard amount > 0 else {
            return
        }

        refreshAccountBalance(for: accountID)
        guard let account = state.accounts[accountID],
              account.creditBalance >= amount
        else {
            throw RelayHTTPError.paymentRequired("Insufficient credit balance.")
        }

        var remaining = amount
        let grantIDs = (state.accounts[accountID]?.grantIDs ?? [])
            .compactMap { state.grants[$0] }
            .filter { $0.isAvailable(now: .now) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
            .map(\.id)

        for grantID in grantIDs where remaining > 0 {
            guard var grant = state.grants[grantID] else {
                continue
            }
            let delta = min(grant.remainingCredits, remaining)
            grant.remainingCredits -= delta
            remaining -= delta
            state.grants[grantID] = grant
        }

        refreshAccountBalance(for: accountID)
    }

    private func refreshAccountBalance(for accountID: UUID) {
        guard var account = state.accounts[accountID] else {
            return
        }
        account.recalculateBalance(grants: state.grants)
        state.accounts[accountID] = account
    }

    private func statusResponse(accountID: UUID, deviceID: String) -> RelayAccountStatusResponse {
        state.compact(now: .now)
        let account = state.accounts[accountID]
        let device = state.devices[deviceID]
        let key = device.flatMap { record in
            record.keyID.flatMap { state.keys[$0] }
        }

        let grants = (account?.grantIDs ?? [])
            .compactMap { state.grants[$0] }
            .filter { $0.isAvailable(now: .now) || $0.remainingCredits > 0 }
            .sorted { $0.grantedAt > $1.grantedAt }
            .map(\.summary)

        let usage = state.usage
            .filter { $0.accountID == accountID }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(RelayBillingStoreConstants.recentUsageLimit)
            .map(\.summary)

        return RelayAccountStatusResponse(
            account: account?.summary,
            device: device?.summary,
            key: key?.summary,
            grants: grants,
            recentUsage: usage
        )
    }

    private func persist() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func loadPersistedStateIfAvailable(
        from fileURL: URL,
        using decoder: JSONDecoder
    ) -> RelayBillingState? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode(RelayBillingState.self, from: data)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("AIChat Relay", isDirectory: true)
            .appendingPathComponent(RelayBillingStoreConstants.stateFilename, isDirectory: false)
    }

    private static func generateClientKey() -> String {
        "rk_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private struct RelayBillingState: Codable, Sendable {
    var accounts: [UUID: RelayBillingAccountRecord]
    var devices: [String: RelayBillingDeviceRecord]
    var keys: [UUID: RelayBillingKeyRecord]
    var grants: [UUID: RelayBillingGrantRecord]
    var usage: [RelayBillingUsageRecord]
    var transactions: [String: RelaySubmittedTransaction]
    var trialClaims: [String: RelayBillingTrialClaimRecord]
    var pairingTokens: [String: RelayPairingTokenRecord]
    var meteringPolicy: RelayMeteringPolicySnapshot
    var plans: [RelayPlanCatalogItem]

    mutating func compact(now: Date) {
        pairingTokens = pairingTokens.filter { $0.value.expiresAt > now }
        usage.sort { $0.createdAt > $1.createdAt }
        if usage.count > 500 {
            usage = Array(usage.prefix(500))
        }

        for accountID in accounts.keys {
            var account = accounts[accountID]!
            account.recalculateBalance(grants: grants)
            accounts[accountID] = account
        }
    }

    func keyRecord(for keyValue: String) -> RelayBillingKeyRecord? {
        keys.values.first(where: { $0.keyValue == keyValue })
    }

    static func makeDefault() -> RelayBillingState {
        RelayBillingState(
            accounts: [:],
            devices: [:],
            keys: [:],
            grants: [:],
            usage: [],
            transactions: [:],
            trialClaims: [:],
            pairingTokens: [:],
            meteringPolicy: RelayMeteringPolicySnapshot(
                creditBudgetUSDPer1000Credits: 1,
                trialCredits: 800,
                trialDurationDays: 7,
                lowBalanceThresholdCredits: 300,
                maxBoundDevices: 5,
                creditMultiplier: 1,
                rates: [
                    RelayMeteringRate(
                        modelID: "gemini-3.1-pro-preview",
                        inputCreditsPerMillion: 2_000,
                        inputCreditsPerMillionOver200k: 4_000,
                        outputCreditsPerMillion: 12_000,
                        outputCreditsPerMillionOver200k: 18_000,
                        audioInputCreditsPerMillion: nil,
                        searchSurchargeCredits: 14
                    ),
                    RelayMeteringRate(
                        modelID: "gemini-3-flash-preview",
                        inputCreditsPerMillion: 500,
                        inputCreditsPerMillionOver200k: nil,
                        outputCreditsPerMillion: 3_000,
                        outputCreditsPerMillionOver200k: nil,
                        audioInputCreditsPerMillion: 1_000,
                        searchSurchargeCredits: 14
                    ),
                    RelayMeteringRate(
                        modelID: "gemini-2.5-flash",
                        inputCreditsPerMillion: 300,
                        inputCreditsPerMillionOver200k: nil,
                        outputCreditsPerMillion: 2_500,
                        outputCreditsPerMillionOver200k: nil,
                        audioInputCreditsPerMillion: 1_000,
                        searchSurchargeCredits: 35
                    )
                ]
            ),
            plans: [
                RelayPlanCatalogItem(id: "starter", title: "Starter", productID: "relay.starter.monthly", priceUSD: 4.99, monthlyCredits: 2_000),
                RelayPlanCatalogItem(id: "plus", title: "Plus", productID: "relay.plus.monthly", priceUSD: 9.99, monthlyCredits: 4_500),
                RelayPlanCatalogItem(id: "pro", title: "Pro", productID: "relay.pro.monthly", priceUSD: 19.99, monthlyCredits: 10_000)
            ]
        )
    }
}

private struct RelayBillingAccountRecord: Codable, Sendable {
    var id: UUID
    var displayName: String?
    var adminNote: String?
    var state: RelayAccountState
    var source: RelayAccessSource
    var planID: String?
    var originalTransactionID: String?
    var appAccountToken: UUID?
    var deviceIDs: [String]
    var keyIDs: [UUID]
    var grantIDs: [UUID]
    var lastUsageAt: Date?
    var creditBalance: Int = 0
    var creditExpiresAt: Date?

    mutating func recalculateBalance(grants: [UUID: RelayBillingGrantRecord]) {
        let availableGrants = grantIDs.compactMap { grants[$0] }.filter { $0.isAvailable(now: .now) }
        self.creditBalance = availableGrants.reduce(into: 0) { partialResult, grant in
            partialResult += max(0, grant.remainingCredits)
        }
        self.creditExpiresAt = availableGrants
            .compactMap(\.expiresAt)
            .sorted()
            .first
    }

    var summary: RelayAccountSummary {
        RelayAccountSummary(
            accountID: id,
            displayName: displayName,
            adminNote: adminNote,
            state: state,
            source: source,
            planID: planID,
            originalTransactionID: originalTransactionID,
            appAccountToken: appAccountToken,
            creditBalance: creditBalance,
            creditExpiresAt: creditExpiresAt,
            lastUsageAt: lastUsageAt
        )
    }
}

private struct RelayBillingDeviceRecord: Codable, Sendable {
    var deviceID: String
    var accountID: UUID
    var platform: RelayDevicePlatform
    var alias: String?
    var note: String?
    var keyID: UUID?
    var lastSeenAt: Date?

    mutating func touch(now: Date) {
        lastSeenAt = now
    }

    var summary: RelayDeviceSummary {
        RelayDeviceSummary(
            deviceID: deviceID,
            platform: platform,
            alias: alias,
            note: note,
            keyID: keyID,
            lastSeenAt: lastSeenAt
        )
    }
}

private struct RelayBillingKeyRecord: Codable, Sendable {
    var id: UUID
    var accountID: UUID
    var deviceID: String
    var keyValue: String
    var state: RelayKeyState
    var source: RelayAccessSource
    var note: String?
    var issuedAt: Date

    var summary: RelayKeySummary {
        RelayKeySummary(
            keyID: id,
            keyValue: keyValue,
            state: state,
            source: source,
            note: note,
            issuedAt: issuedAt
        )
    }
}

private struct RelayBillingGrantRecord: Codable, Sendable {
    var id: UUID
    var accountID: UUID
    var source: RelayAccessSource
    var totalCredits: Int
    var remainingCredits: Int
    var grantedAt: Date
    var expiresAt: Date?
    var sourceTransactionID: String?
    var note: String?

    func isAvailable(now: Date) -> Bool {
        remainingCredits > 0 && (expiresAt == nil || expiresAt! > now)
    }

    var summary: RelayGrantSummary {
        RelayGrantSummary(
            grantID: id,
            source: source,
            totalCredits: totalCredits,
            remainingCredits: remainingCredits,
            grantedAt: grantedAt,
            expiresAt: expiresAt,
            note: note
        )
    }
}

private struct RelayBillingUsageRecord: Codable, Sendable {
    var requestID: UUID
    var accountID: UUID
    var deviceID: String
    var keyID: UUID
    var endpoint: String
    var modelID: String
    var inputTokens: Int
    var outputTokens: Int
    var reservedCredits: Int
    var settledCredits: Int
    var searchCount: Int
    var createdAt: Date

    var summary: RelayUsageSummary {
        RelayUsageSummary(
            requestID: requestID,
            endpoint: endpoint,
            modelID: modelID,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            reservedCredits: reservedCredits,
            settledCredits: settledCredits,
            searchCount: searchCount,
            createdAt: createdAt
        )
    }
}

private struct RelayBillingTrialClaimRecord: Codable, Sendable {
    var deviceID: String
    var grantID: UUID
    var claimedAt: Date
}

private struct RelayPairingTokenRecord: Codable, Sendable {
    var token: String
    var accountID: UUID
    var createdByDeviceID: String
    var expiresAt: Date
}

private struct RelayNormalizedSubmittedTransaction: Sendable {
    var transaction: RelaySubmittedTransaction
    var appAccountToken: UUID?
}

private struct RelayAppStoreTransactionPayload: Decodable, Sendable {
    var transactionID: String
    var originalTransactionID: String?
    var productID: String
    var environment: String?
    var purchaseDate: Date?
    var expirationDate: Date?
    var revocationDate: Date?
    var appAccountToken: UUID?

    enum CodingKeys: String, CodingKey {
        case transactionID = "transactionId"
        case originalTransactionID = "originalTransactionId"
        case productID = "productId"
        case environment
        case purchaseDate
        case expirationDate = "expiresDate"
        case revocationDate
        case appAccountToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        originalTransactionID = try container.decodeIfPresent(String.self, forKey: .originalTransactionID)
        productID = try container.decode(String.self, forKey: .productID)
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
        purchaseDate = try container.decodeFlexibleDateIfPresent(forKey: .purchaseDate)
        expirationDate = try container.decodeFlexibleDateIfPresent(forKey: .expirationDate)
        revocationDate = try container.decodeFlexibleDateIfPresent(forKey: .revocationDate)
        if let tokenString = try container.decodeIfPresent(String.self, forKey: .appAccountToken)?.nonEmptyTrimmed {
            guard let token = UUID(uuidString: tokenString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .appAccountToken,
                    in: container,
                    debugDescription: "Invalid appAccountToken UUID."
                )
            }
            appAccountToken = token
        } else {
            appAccountToken = nil
        }
    }

    static func decode(fromJWS value: String) throws -> RelayAppStoreTransactionPayload {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payloadData = Data(base64URLEncoded: String(segments[1])) else {
            throw RelayHTTPError.badRequest("Invalid signed transaction payload.")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RelayAppStoreTransactionPayload.self, from: payloadData)
    }
}

private extension KeyedDecodingContainer where K == RelayAppStoreTransactionPayload.CodingKeys {
    func decodeFlexibleDateIfPresent(forKey key: K) throws -> Date? {
        if let milliseconds = try? decode(Int64.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }

        if let millisecondsString = try? decode(String.self, forKey: key),
           let milliseconds = Int64(millisecondsString) {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }

        if let millisecondsDouble = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: millisecondsDouble / 1_000)
        }

        return nil
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: normalized)
    }
}
