import Foundation

private extension KeyedDecodingContainer {
    nonisolated func decodeFirstPresent<T: Decodable>(
        _ type: T.Type,
        forKeys keys: [Key]
    ) throws -> T {
        for key in keys where contains(key) {
            return try decode(T.self, forKey: key)
        }

        let missingKey = keys.first ?? Key(stringValue: "unknown")!
        throw DecodingError.keyNotFound(
            missingKey,
            DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Missing required key \(missingKey.stringValue)."
            )
        )
    }

    nonisolated func decodeIfPresentFirst<T: Decodable>(
        _ type: T.Type,
        forKeys keys: [Key]
    ) throws -> T? {
        for key in keys where contains(key) {
            return try decodeIfPresent(T.self, forKey: key)
        }

        return nil
    }
}

nonisolated enum RelayAccessSource: String, Codable, CaseIterable, Sendable {
    case trial
    case subscription
    case offlineManual
}

nonisolated enum RelayAccountState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case expired
    case inactive
}

nonisolated enum RelayKeyState: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case revoked
}

nonisolated enum RelayDevicePlatform: String, Codable, CaseIterable, Sendable {
    case iPhone
    case watch
    case mac
    case unknown
}

nonisolated struct RelayPlanCatalogItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var productID: String
    var priceUSD: Decimal
    var monthlyCredits: Int
}

nonisolated struct RelayMeteringRate: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { modelID }
    var modelID: String
    var inputCreditsPerMillion: Int
    var inputCreditsPerMillionOver200k: Int?
    var outputCreditsPerMillion: Int
    var outputCreditsPerMillionOver200k: Int?
    var audioInputCreditsPerMillion: Int?
    var searchSurchargeCredits: Int
}

nonisolated struct RelayMeteringPolicySnapshot: Codable, Equatable, Hashable, Sendable {
    var creditBudgetUSDPer1000Credits: Decimal
    var trialCredits: Int
    var trialDurationDays: Int
    var lowBalanceThresholdCredits: Int
    var maxBoundDevices: Int
    var creditMultiplier: Decimal
    var rates: [RelayMeteringRate]
}

nonisolated struct RelayCatalogResponse: Codable, Equatable, Sendable {
    var plans: [RelayPlanCatalogItem]
    var meteringPolicy: RelayMeteringPolicySnapshot
}

nonisolated struct RelayAccountSummary: Codable, Equatable, Hashable, Sendable {
    var accountID: UUID
    var displayName: String?
    var adminNote: String?
    var state: RelayAccountState
    var source: RelayAccessSource
    var planID: String?
    var originalTransactionID: String?
    var appAccountToken: UUID?
    var creditBalance: Int
    var creditExpiresAt: Date?
    var lastUsageAt: Date?

    private enum CodingKeys: String, CodingKey {
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
        case displayName
        case displayNameSnake = "display_name"
        case adminNote
        case adminNoteSnake = "admin_note"
        case state
        case source
        case planID
        case planIDConverted = "planId"
        case planIDSnake = "plan_id"
        case originalTransactionID
        case originalTransactionIDConverted = "originalTransactionId"
        case originalTransactionIDSnake = "original_transaction_id"
        case appAccountToken
        case appAccountTokenSnake = "app_account_token"
        case creditBalance
        case creditBalanceSnake = "credit_balance"
        case creditExpiresAt
        case creditExpiresAtSnake = "credit_expires_at"
        case lastUsageAt
        case lastUsageAtSnake = "last_usage_at"
    }

    init(
        accountID: UUID,
        displayName: String?,
        adminNote: String?,
        state: RelayAccountState,
        source: RelayAccessSource,
        planID: String?,
        originalTransactionID: String?,
        appAccountToken: UUID?,
        creditBalance: Int,
        creditExpiresAt: Date?,
        lastUsageAt: Date?
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.adminNote = adminNote
        self.state = state
        self.source = source
        self.planID = planID
        self.originalTransactionID = originalTransactionID
        self.appAccountToken = appAccountToken
        self.creditBalance = creditBalance
        self.creditExpiresAt = creditExpiresAt
        self.lastUsageAt = lastUsageAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decodeFirstPresent(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
        displayName = try container.decodeIfPresentFirst(String.self, forKeys: [.displayName, .displayNameSnake])
        adminNote = try container.decodeIfPresentFirst(String.self, forKeys: [.adminNote, .adminNoteSnake])
        state = try container.decode(RelayAccountState.self, forKey: .state)
        source = try container.decode(RelayAccessSource.self, forKey: .source)
        planID = try container.decodeIfPresentFirst(String.self, forKeys: [.planID, .planIDConverted, .planIDSnake])
        originalTransactionID = try container.decodeIfPresentFirst(
            String.self,
            forKeys: [.originalTransactionID, .originalTransactionIDConverted, .originalTransactionIDSnake]
        )
        appAccountToken = try container.decodeIfPresentFirst(
            UUID.self,
            forKeys: [.appAccountToken, .appAccountTokenSnake]
        )
        creditBalance = try container.decodeFirstPresent(Int.self, forKeys: [.creditBalance, .creditBalanceSnake])
        creditExpiresAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.creditExpiresAt, .creditExpiresAtSnake])
        lastUsageAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.lastUsageAt, .lastUsageAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountID, forKey: .accountID)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(adminNote, forKey: .adminNote)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(planID, forKey: .planID)
        try container.encodeIfPresent(originalTransactionID, forKey: .originalTransactionID)
        try container.encodeIfPresent(appAccountToken, forKey: .appAccountToken)
        try container.encode(creditBalance, forKey: .creditBalance)
        try container.encodeIfPresent(creditExpiresAt, forKey: .creditExpiresAt)
        try container.encodeIfPresent(lastUsageAt, forKey: .lastUsageAt)
    }
}

nonisolated struct RelayDeviceSummary: Codable, Equatable, Hashable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var alias: String?
    var note: String?
    var keyID: UUID?
    var lastSeenAt: Date?

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case alias
        case note
        case keyID
        case keyIDConverted = "keyId"
        case keyIDSnake = "key_id"
        case lastSeenAt
        case lastSeenAtSnake = "last_seen_at"
    }

    init(
        deviceID: String,
        platform: RelayDevicePlatform,
        alias: String?,
        note: String?,
        keyID: UUID?,
        lastSeenAt: Date?
    ) {
        self.deviceID = deviceID
        self.platform = platform
        self.alias = alias
        self.note = note
        self.keyID = keyID
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        keyID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.keyID, .keyIDConverted, .keyIDSnake])
        lastSeenAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.lastSeenAt, .lastSeenAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(keyID, forKey: .keyID)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
    }
}

nonisolated struct RelayKeySummary: Codable, Equatable, Hashable, Sendable {
    var keyID: UUID
    var keyValue: String
    var state: RelayKeyState
    var source: RelayAccessSource
    var note: String?
    var issuedAt: Date

    private enum CodingKeys: String, CodingKey {
        case keyID
        case keyIDConverted = "keyId"
        case keyIDSnake = "key_id"
        case keyValue
        case keyValueSnake = "key_value"
        case state
        case source
        case note
        case issuedAt
        case issuedAtSnake = "issued_at"
    }

    init(
        keyID: UUID,
        keyValue: String,
        state: RelayKeyState,
        source: RelayAccessSource,
        note: String?,
        issuedAt: Date
    ) {
        self.keyID = keyID
        self.keyValue = keyValue
        self.state = state
        self.source = source
        self.note = note
        self.issuedAt = issuedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyID = try container.decodeFirstPresent(UUID.self, forKeys: [.keyID, .keyIDConverted, .keyIDSnake])
        keyValue = try container.decodeFirstPresent(String.self, forKeys: [.keyValue, .keyValueSnake])
        state = try container.decode(RelayKeyState.self, forKey: .state)
        source = try container.decode(RelayAccessSource.self, forKey: .source)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        issuedAt = try container.decodeFirstPresent(Date.self, forKeys: [.issuedAt, .issuedAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyID, forKey: .keyID)
        try container.encode(keyValue, forKey: .keyValue)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(issuedAt, forKey: .issuedAt)
    }
}

nonisolated struct RelayGrantSummary: Codable, Equatable, Hashable, Sendable {
    var grantID: UUID
    var source: RelayAccessSource
    var totalCredits: Int
    var remainingCredits: Int
    var grantedAt: Date
    var expiresAt: Date?
    var note: String?
}

nonisolated struct RelayUsageSummary: Codable, Equatable, Hashable, Sendable {
    var requestID: UUID
    var endpoint: String
    var modelID: String
    var inputTokens: Int
    var outputTokens: Int
    var reservedCredits: Int
    var settledCredits: Int
    var searchCount: Int
    var createdAt: Date
}

nonisolated struct RelayAccountStatusResponse: Codable, Equatable, Sendable {
    var account: RelayAccountSummary?
    var device: RelayDeviceSummary?
    var key: RelayKeySummary?
    var grants: [RelayGrantSummary]
    var recentUsage: [RelayUsageSummary]

    private enum CodingKeys: String, CodingKey {
        case account
        case device
        case key
        case grants
        case recentUsage
    }

    init(
        account: RelayAccountSummary?,
        device: RelayDeviceSummary?,
        key: RelayKeySummary?,
        grants: [RelayGrantSummary],
        recentUsage: [RelayUsageSummary]
    ) {
        self.account = account
        self.device = device
        self.key = key
        self.grants = grants
        self.recentUsage = recentUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try? container.decodeIfPresent(RelayAccountSummary.self, forKey: .account)
        device = try? container.decodeIfPresent(RelayDeviceSummary.self, forKey: .device)
        key = try? container.decodeIfPresent(RelayKeySummary.self, forKey: .key)
        grants = (try? container.decodeIfPresent([RelayGrantSummary].self, forKey: .grants)) ?? []
        recentUsage = (try? container.decodeIfPresent([RelayUsageSummary].self, forKey: .recentUsage)) ?? []
    }
}

nonisolated struct RelayActivationBootstrapRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var deviceAlias: String?
}

nonisolated struct RelayPurchasePrepareRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
}

nonisolated struct RelayPurchasePrepareResponse: Codable, Equatable, Sendable {
    var accountID: UUID
    var appAccountToken: UUID
}

nonisolated struct RelaySubmittedTransaction: Codable, Equatable, Hashable, Sendable {
    var transactionID: String
    var originalTransactionID: String?
    var productID: String
    var environment: String?
    var signedTransactionInfo: String?
    var signedRenewalInfo: String?
    var purchaseDate: Date?
    var expirationDate: Date?
    var revokedDate: Date?
}

nonisolated struct RelayPurchaseSubmitRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var transaction: RelaySubmittedTransaction
}

nonisolated struct RelayRestorePurchasesRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var transactions: [RelaySubmittedTransaction]
}

nonisolated struct RelayPairingTokenResponse: Codable, Equatable, Sendable {
    var pairingToken: String
    var expiresAt: Date
}

nonisolated struct RelayJoinPairedRequest: Codable, Equatable, Sendable {
    var pairingToken: String
    var deviceID: String
    var platform: RelayDevicePlatform
    var deviceAlias: String?
}

nonisolated struct RelayOfflineExchangeRequest: Codable, Equatable, Sendable {
    var activationCode: String
    var deviceID: String
    var platform: RelayDevicePlatform
    var deviceAlias: String?
    var creditsTotal: Int?
    var creditsRemaining: Int?
    var validUntil: Date?
    var allowedModelIDs: [String]?
    var activationFingerprint: String?
}

nonisolated struct RelayPurchaseSubmissionResponse: Codable, Equatable, Sendable {
    var status: RelayAccountStatusResponse
}
