import Foundation
import os

private let relayBillingContractLog = Logger(subsystem: "com.aichat.shared", category: "RelayBillingContracts")

/// Wire format version negotiated between Swift clients and the TS relay server.
/// Increment alongside any breaking change to the contracts in this file.
nonisolated let RelayContractVersion: Int = 2

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

/// TS contract: `"trial" | "subscription" | "offlineManual"` (see `relay/src/lib/billing/types.ts:8`).
/// Carries an `unknown(rawValue)` fallback so a future server-side enum value (e.g. `"promo"`)
/// does not silently nuke the entire `RelayAccountStatusResponse` once `try?` traps are removed.
nonisolated enum RelayAccessSource: RawRepresentable, Codable, Hashable, Sendable, CaseIterable {
    case trial
    case subscription
    case offlineManual
    case unknown(String)

    static var allCases: [RelayAccessSource] {
        [.trial, .subscription, .offlineManual]
    }

    init(rawValue: String) {
        switch rawValue {
        case "trial": self = .trial
        case "subscription": self = .subscription
        case "offlineManual": self = .offlineManual
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .trial: return "trial"
        case .subscription: return "subscription"
        case .offlineManual: return "offlineManual"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// TS contract: `"active" | "paused" | "expired" | "inactive"` (see `relay/src/lib/billing/types.ts`).
nonisolated enum RelayAccountState: RawRepresentable, Codable, Hashable, Sendable, CaseIterable {
    case active
    case paused
    case expired
    case inactive
    case unknown(String)

    static var allCases: [RelayAccountState] {
        [.active, .paused, .expired, .inactive]
    }

    init(rawValue: String) {
        switch rawValue {
        case "active": self = .active
        case "paused": self = .paused
        case "expired": self = .expired
        case "inactive": self = .inactive
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .active: return "active"
        case .paused: return "paused"
        case .expired: return "expired"
        case .inactive: return "inactive"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// TS contract: `"active" | "paused" | "revoked"` (see `relay/src/lib/billing/types.ts`).
nonisolated enum RelayKeyState: RawRepresentable, Codable, Hashable, Sendable, CaseIterable {
    case active
    case paused
    case revoked
    case unknown(String)

    static var allCases: [RelayKeyState] {
        [.active, .paused, .revoked]
    }

    init(rawValue: String) {
        switch rawValue {
        case "active": self = .active
        case "paused": self = .paused
        case "revoked": self = .revoked
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .active: return "active"
        case .paused: return "paused"
        case .revoked: return "revoked"
        case .unknown(let value): return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

/// TODO(contract-versioning): wire this through the network layer once the relay
/// server starts emitting `meta.schemaVersion`. Today the type is unused but
/// reserved so we can opt-in without another contract churn round.
nonisolated struct RelayContractEnvelope<T: Decodable>: Decodable, Sendable where T: Sendable {
    let meta: Meta?
    let payload: T

    nonisolated struct Meta: Decodable, Sendable {
        let schemaVersion: Int?
    }
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
    /// Optional on Swift even though TS marks them required, so older watch builds
    /// keep decoding when the server adds these. See `relay/src/lib/billing/types.ts:24-27`.
    var deviceIDs: [String]?
    var keyIDs: [String]?
    var grantIDs: [String]?
    var createdAt: Date?

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
        case deviceIDs
        case deviceIDsConverted = "deviceIds"
        case deviceIDsSnake = "device_ids"
        case keyIDs
        case keyIDsConverted = "keyIds"
        case keyIDsSnake = "key_ids"
        case grantIDs
        case grantIDsConverted = "grantIds"
        case grantIDsSnake = "grant_ids"
        case createdAt
        case createdAtSnake = "created_at"
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
        lastUsageAt: Date?,
        deviceIDs: [String]? = nil,
        keyIDs: [String]? = nil,
        grantIDs: [String]? = nil,
        createdAt: Date? = nil
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
        self.deviceIDs = deviceIDs
        self.keyIDs = keyIDs
        self.grantIDs = grantIDs
        self.createdAt = createdAt
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
        deviceIDs = try container.decodeIfPresentFirst([String].self, forKeys: [.deviceIDs, .deviceIDsConverted, .deviceIDsSnake])
        keyIDs = try container.decodeIfPresentFirst([String].self, forKeys: [.keyIDs, .keyIDsConverted, .keyIDsSnake])
        grantIDs = try container.decodeIfPresentFirst([String].self, forKeys: [.grantIDs, .grantIDsConverted, .grantIDsSnake])
        createdAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.createdAt, .createdAtSnake])
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
        try container.encodeIfPresent(deviceIDs, forKey: .deviceIDs)
        try container.encodeIfPresent(keyIDs, forKey: .keyIDs)
        try container.encodeIfPresent(grantIDs, forKey: .grantIDs)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

nonisolated struct RelayDeviceSummary: Codable, Equatable, Hashable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var alias: String?
    var note: String?
    var keyID: UUID?
    var lastSeenAt: Date?
    /// TS contract requires `accountID`. Kept optional on Swift so older builds keep decoding.
    var accountID: UUID?

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
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
    }

    init(
        deviceID: String,
        platform: RelayDevicePlatform,
        alias: String?,
        note: String?,
        keyID: UUID?,
        lastSeenAt: Date?,
        accountID: UUID? = nil
    ) {
        self.deviceID = deviceID
        self.platform = platform
        self.alias = alias
        self.note = note
        self.keyID = keyID
        self.lastSeenAt = lastSeenAt
        self.accountID = accountID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        keyID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.keyID, .keyIDConverted, .keyIDSnake])
        lastSeenAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.lastSeenAt, .lastSeenAtSnake])
        accountID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(keyID, forKey: .keyID)
        try container.encodeIfPresent(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(accountID, forKey: .accountID)
    }
}

nonisolated struct RelayKeySummary: Codable, Equatable, Hashable, Sendable {
    var keyID: UUID
    /// `keyValue` is being phased out; the server stops echoing it post-A1 strip. Kept optional
    /// so historic responses still decode and so existing callers compile unchanged.
    var keyValue: String?
    var state: RelayKeyState
    var source: RelayAccessSource
    var note: String?
    var issuedAt: Date
    /// TS additions — required server-side, optional on Swift for forward compat.
    var accountID: UUID?
    var lastUsedAt: Date?

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
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
        case lastUsedAt
        case lastUsedAtSnake = "last_used_at"
    }

    init(
        keyID: UUID,
        keyValue: String?,
        state: RelayKeyState,
        source: RelayAccessSource,
        note: String?,
        issuedAt: Date,
        accountID: UUID? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.keyID = keyID
        self.keyValue = keyValue
        self.state = state
        self.source = source
        self.note = note
        self.issuedAt = issuedAt
        self.accountID = accountID
        self.lastUsedAt = lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyID = try container.decodeFirstPresent(UUID.self, forKeys: [.keyID, .keyIDConverted, .keyIDSnake])
        keyValue = try container.decodeIfPresentFirst(String.self, forKeys: [.keyValue, .keyValueSnake])
        state = try container.decode(RelayKeyState.self, forKey: .state)
        source = try container.decode(RelayAccessSource.self, forKey: .source)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        issuedAt = try container.decodeFirstPresent(Date.self, forKeys: [.issuedAt, .issuedAtSnake])
        accountID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
        lastUsedAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.lastUsedAt, .lastUsedAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyID, forKey: .keyID)
        try container.encodeIfPresent(keyValue, forKey: .keyValue)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
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
    /// TS additions — required server-side, optional on Swift for forward compat.
    var accountID: UUID?
    var sourceTransactionID: String?

    private enum CodingKeys: String, CodingKey {
        case grantID
        case grantIDConverted = "grantId"
        case grantIDSnake = "grant_id"
        case source
        case totalCredits
        case totalCreditsSnake = "total_credits"
        case remainingCredits
        case remainingCreditsSnake = "remaining_credits"
        case grantedAt
        case grantedAtSnake = "granted_at"
        case expiresAt
        case expiresAtSnake = "expires_at"
        case note
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
        case sourceTransactionID
        case sourceTransactionIDConverted = "sourceTransactionId"
        case sourceTransactionIDSnake = "source_transaction_id"
    }

    init(
        grantID: UUID,
        source: RelayAccessSource,
        totalCredits: Int,
        remainingCredits: Int,
        grantedAt: Date,
        expiresAt: Date?,
        note: String?,
        accountID: UUID? = nil,
        sourceTransactionID: String? = nil
    ) {
        self.grantID = grantID
        self.source = source
        self.totalCredits = totalCredits
        self.remainingCredits = remainingCredits
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.note = note
        self.accountID = accountID
        self.sourceTransactionID = sourceTransactionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        grantID = try container.decodeFirstPresent(UUID.self, forKeys: [.grantID, .grantIDConverted, .grantIDSnake])
        source = try container.decode(RelayAccessSource.self, forKey: .source)
        totalCredits = try container.decodeFirstPresent(Int.self, forKeys: [.totalCredits, .totalCreditsSnake])
        remainingCredits = try container.decodeFirstPresent(Int.self, forKeys: [.remainingCredits, .remainingCreditsSnake])
        grantedAt = try container.decodeFirstPresent(Date.self, forKeys: [.grantedAt, .grantedAtSnake])
        expiresAt = try container.decodeIfPresentFirst(Date.self, forKeys: [.expiresAt, .expiresAtSnake])
        note = try container.decodeIfPresent(String.self, forKey: .note)
        accountID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
        sourceTransactionID = try container.decodeIfPresentFirst(
            String.self,
            forKeys: [.sourceTransactionID, .sourceTransactionIDConverted, .sourceTransactionIDSnake]
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(grantID, forKey: .grantID)
        try container.encode(source, forKey: .source)
        try container.encode(totalCredits, forKey: .totalCredits)
        try container.encode(remainingCredits, forKey: .remainingCredits)
        try container.encode(grantedAt, forKey: .grantedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encodeIfPresent(sourceTransactionID, forKey: .sourceTransactionID)
    }
}

nonisolated struct RelayUsageSummary: Codable, Equatable, Hashable, Sendable {
    var requestID: UUID
    var endpoint: String
    /// TS contract: `modelID?: string` (`relay/src/lib/billing/types.ts:71`). A single null model
    /// in `recentUsage` previously crashed the entire response decode and silently nuked the list
    /// because `RelayAccountStatusResponse.init` swallowed it with `try?`.
    var modelID: String?
    var inputTokens: Int
    var outputTokens: Int
    var reservedCredits: Int
    var settledCredits: Int
    var searchCount: Int
    var createdAt: Date
    /// TS additions — optional both sides.
    var accountID: UUID?
    var deviceID: String?
    var keyID: UUID?

    private enum CodingKeys: String, CodingKey {
        case requestID
        case requestIDConverted = "requestId"
        case requestIDSnake = "request_id"
        case endpoint
        case modelID
        case modelIDConverted = "modelId"
        case modelIDSnake = "model_id"
        case inputTokens
        case inputTokensSnake = "input_tokens"
        case outputTokens
        case outputTokensSnake = "output_tokens"
        case reservedCredits
        case reservedCreditsSnake = "reserved_credits"
        case settledCredits
        case settledCreditsSnake = "settled_credits"
        case searchCount
        case searchCountSnake = "search_count"
        case createdAt
        case createdAtSnake = "created_at"
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case keyID
        case keyIDConverted = "keyId"
        case keyIDSnake = "key_id"
    }

    init(
        requestID: UUID,
        endpoint: String,
        modelID: String?,
        inputTokens: Int,
        outputTokens: Int,
        reservedCredits: Int,
        settledCredits: Int,
        searchCount: Int,
        createdAt: Date,
        accountID: UUID? = nil,
        deviceID: String? = nil,
        keyID: UUID? = nil
    ) {
        self.requestID = requestID
        self.endpoint = endpoint
        self.modelID = modelID
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reservedCredits = reservedCredits
        self.settledCredits = settledCredits
        self.searchCount = searchCount
        self.createdAt = createdAt
        self.accountID = accountID
        self.deviceID = deviceID
        self.keyID = keyID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decodeFirstPresent(UUID.self, forKeys: [.requestID, .requestIDConverted, .requestIDSnake])
        endpoint = try container.decode(String.self, forKey: .endpoint)
        modelID = try container.decodeIfPresentFirst(String.self, forKeys: [.modelID, .modelIDConverted, .modelIDSnake])
        inputTokens = try container.decodeFirstPresent(Int.self, forKeys: [.inputTokens, .inputTokensSnake])
        outputTokens = try container.decodeFirstPresent(Int.self, forKeys: [.outputTokens, .outputTokensSnake])
        reservedCredits = try container.decodeFirstPresent(Int.self, forKeys: [.reservedCredits, .reservedCreditsSnake])
        settledCredits = try container.decodeFirstPresent(Int.self, forKeys: [.settledCredits, .settledCreditsSnake])
        searchCount = try container.decodeFirstPresent(Int.self, forKeys: [.searchCount, .searchCountSnake])
        createdAt = try container.decodeFirstPresent(Date.self, forKeys: [.createdAt, .createdAtSnake])
        accountID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
        deviceID = try container.decodeIfPresentFirst(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        keyID = try container.decodeIfPresentFirst(UUID.self, forKeys: [.keyID, .keyIDConverted, .keyIDSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encodeIfPresent(modelID, forKey: .modelID)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(reservedCredits, forKey: .reservedCredits)
        try container.encode(settledCredits, forKey: .settledCredits)
        try container.encode(searchCount, forKey: .searchCount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(accountID, forKey: .accountID)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encodeIfPresent(keyID, forKey: .keyID)
    }
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
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `account` is genuinely optional on the wire (no online account bound yet).
            account = try container.decodeIfPresent(RelayAccountSummary.self, forKey: .account)
            // `device` and `key` follow the same per-device-binding convention.
            device = try container.decodeIfPresent(RelayDeviceSummary.self, forKey: .device)
            key = try container.decodeIfPresent(RelayKeySummary.self, forKey: .key)
            // TS sends `grants` and `recentUsage` as required arrays (possibly empty). Decode strictly
            // — silent fallbacks here are exactly how prior schema drift hid online-billing visibility.
            grants = try container.decodeIfPresent([RelayGrantSummary].self, forKey: .grants) ?? []
            recentUsage = try container.decodeIfPresent([RelayUsageSummary].self, forKey: .recentUsage) ?? []
        } catch {
            relayBillingContractLog.error(
                "RelayAccountStatusResponse decode failed: \(String(describing: error), privacy: .public)"
            )
            throw error
        }
    }
}

nonisolated struct RelayActivationBootstrapRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var deviceAlias: String?

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case deviceAlias
        case deviceAliasSnake = "device_alias"
    }

    init(deviceID: String, platform: RelayDevicePlatform, deviceAlias: String?) {
        self.deviceID = deviceID
        self.platform = platform
        self.deviceAlias = deviceAlias
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        deviceAlias = try container.decodeIfPresentFirst(String.self, forKeys: [.deviceAlias, .deviceAliasSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(deviceAlias, forKey: .deviceAlias)
    }
}

nonisolated struct RelayPurchasePrepareRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
    }

    init(deviceID: String, platform: RelayDevicePlatform) {
        self.deviceID = deviceID
        self.platform = platform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
    }
}

nonisolated struct RelayPurchasePrepareResponse: Codable, Equatable, Sendable {
    var accountID: UUID
    var appAccountToken: UUID

    private enum CodingKeys: String, CodingKey {
        case accountID
        case accountIDConverted = "accountId"
        case accountIDSnake = "account_id"
        case appAccountToken
        case appAccountTokenSnake = "app_account_token"
    }

    init(accountID: UUID, appAccountToken: UUID) {
        self.accountID = accountID
        self.appAccountToken = appAccountToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decodeFirstPresent(UUID.self, forKeys: [.accountID, .accountIDConverted, .accountIDSnake])
        appAccountToken = try container.decodeFirstPresent(UUID.self, forKeys: [.appAccountToken, .appAccountTokenSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(appAccountToken, forKey: .appAccountToken)
    }
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

    private enum CodingKeys: String, CodingKey {
        case transactionID
        case transactionIDConverted = "transactionId"
        case transactionIDSnake = "transaction_id"
        case originalTransactionID
        case originalTransactionIDConverted = "originalTransactionId"
        case originalTransactionIDSnake = "original_transaction_id"
        case productID
        case productIDConverted = "productId"
        case productIDSnake = "product_id"
        case environment
        case signedTransactionInfo
        case signedTransactionInfoSnake = "signed_transaction_info"
        case signedRenewalInfo
        case signedRenewalInfoSnake = "signed_renewal_info"
        case purchaseDate
        case purchaseDateSnake = "purchase_date"
        case expirationDate
        case expirationDateSnake = "expiration_date"
        case revokedDate
        case revokedDateSnake = "revoked_date"
    }

    init(
        transactionID: String,
        originalTransactionID: String?,
        productID: String,
        environment: String?,
        signedTransactionInfo: String?,
        signedRenewalInfo: String?,
        purchaseDate: Date?,
        expirationDate: Date?,
        revokedDate: Date?
    ) {
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.productID = productID
        self.environment = environment
        self.signedTransactionInfo = signedTransactionInfo
        self.signedRenewalInfo = signedRenewalInfo
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revokedDate = revokedDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decodeFirstPresent(String.self, forKeys: [.transactionID, .transactionIDConverted, .transactionIDSnake])
        originalTransactionID = try container.decodeIfPresentFirst(String.self, forKeys: [.originalTransactionID, .originalTransactionIDConverted, .originalTransactionIDSnake])
        productID = try container.decodeFirstPresent(String.self, forKeys: [.productID, .productIDConverted, .productIDSnake])
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
        signedTransactionInfo = try container.decodeIfPresentFirst(String.self, forKeys: [.signedTransactionInfo, .signedTransactionInfoSnake])
        signedRenewalInfo = try container.decodeIfPresentFirst(String.self, forKeys: [.signedRenewalInfo, .signedRenewalInfoSnake])
        purchaseDate = try container.decodeIfPresentFirst(Date.self, forKeys: [.purchaseDate, .purchaseDateSnake])
        expirationDate = try container.decodeIfPresentFirst(Date.self, forKeys: [.expirationDate, .expirationDateSnake])
        revokedDate = try container.decodeIfPresentFirst(Date.self, forKeys: [.revokedDate, .revokedDateSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encodeIfPresent(originalTransactionID, forKey: .originalTransactionID)
        try container.encode(productID, forKey: .productID)
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encodeIfPresent(signedTransactionInfo, forKey: .signedTransactionInfo)
        try container.encodeIfPresent(signedRenewalInfo, forKey: .signedRenewalInfo)
        try container.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
        try container.encodeIfPresent(expirationDate, forKey: .expirationDate)
        try container.encodeIfPresent(revokedDate, forKey: .revokedDate)
    }
}

nonisolated struct RelayPurchaseSubmitRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var transaction: RelaySubmittedTransaction

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case transaction
    }

    init(deviceID: String, platform: RelayDevicePlatform, transaction: RelaySubmittedTransaction) {
        self.deviceID = deviceID
        self.platform = platform
        self.transaction = transaction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        transaction = try container.decode(RelaySubmittedTransaction.self, forKey: .transaction)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encode(transaction, forKey: .transaction)
    }
}

nonisolated struct RelayRestorePurchasesRequest: Codable, Equatable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var transactions: [RelaySubmittedTransaction]

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case transactions
    }

    init(deviceID: String, platform: RelayDevicePlatform, transactions: [RelaySubmittedTransaction]) {
        self.deviceID = deviceID
        self.platform = platform
        self.transactions = transactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        transactions = try container.decode([RelaySubmittedTransaction].self, forKey: .transactions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encode(transactions, forKey: .transactions)
    }
}

nonisolated struct RelayPairingTokenResponse: Codable, Equatable, Sendable {
    var pairingToken: String
    var expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case pairingToken
        case pairingTokenSnake = "pairing_token"
        case expiresAt
        case expiresAtSnake = "expires_at"
    }

    init(pairingToken: String, expiresAt: Date) {
        self.pairingToken = pairingToken
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairingToken = try container.decodeFirstPresent(String.self, forKeys: [.pairingToken, .pairingTokenSnake])
        expiresAt = try container.decodeFirstPresent(Date.self, forKeys: [.expiresAt, .expiresAtSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pairingToken, forKey: .pairingToken)
        try container.encode(expiresAt, forKey: .expiresAt)
    }
}

nonisolated struct RelayJoinPairedRequest: Codable, Equatable, Sendable {
    var pairingToken: String
    var deviceID: String
    var platform: RelayDevicePlatform
    var deviceAlias: String?

    private enum CodingKeys: String, CodingKey {
        case pairingToken
        case pairingTokenSnake = "pairing_token"
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case deviceAlias
        case deviceAliasSnake = "device_alias"
    }

    init(pairingToken: String, deviceID: String, platform: RelayDevicePlatform, deviceAlias: String?) {
        self.pairingToken = pairingToken
        self.deviceID = deviceID
        self.platform = platform
        self.deviceAlias = deviceAlias
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairingToken = try container.decodeFirstPresent(String.self, forKeys: [.pairingToken, .pairingTokenSnake])
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        deviceAlias = try container.decodeIfPresentFirst(String.self, forKeys: [.deviceAlias, .deviceAliasSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pairingToken, forKey: .pairingToken)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(deviceAlias, forKey: .deviceAlias)
    }
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

    private enum CodingKeys: String, CodingKey {
        case activationCode
        case activationCodeSnake = "activation_code"
        case deviceID
        case deviceIDConverted = "deviceId"
        case deviceIDSnake = "device_id"
        case platform
        case deviceAlias
        case deviceAliasSnake = "device_alias"
        case creditsTotal
        case creditsTotalSnake = "credits_total"
        case creditsRemaining
        case creditsRemainingSnake = "credits_remaining"
        case validUntil
        case validUntilSnake = "valid_until"
        case allowedModelIDs
        case allowedModelIDsConverted = "allowedModelIds"
        case allowedModelIDsSnake = "allowed_model_ids"
        case allowedModelIDsSnakeBuggy = "allowed_model_i_ds"
        case activationFingerprint
        case activationFingerprintSnake = "activation_fingerprint"
    }

    init(
        activationCode: String,
        deviceID: String,
        platform: RelayDevicePlatform,
        deviceAlias: String?,
        creditsTotal: Int?,
        creditsRemaining: Int?,
        validUntil: Date?,
        allowedModelIDs: [String]?,
        activationFingerprint: String?
    ) {
        self.activationCode = activationCode
        self.deviceID = deviceID
        self.platform = platform
        self.deviceAlias = deviceAlias
        self.creditsTotal = creditsTotal
        self.creditsRemaining = creditsRemaining
        self.validUntil = validUntil
        self.allowedModelIDs = allowedModelIDs
        self.activationFingerprint = activationFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activationCode = try container.decodeFirstPresent(String.self, forKeys: [.activationCode, .activationCodeSnake])
        deviceID = try container.decodeFirstPresent(String.self, forKeys: [.deviceID, .deviceIDConverted, .deviceIDSnake])
        platform = try container.decode(RelayDevicePlatform.self, forKey: .platform)
        deviceAlias = try container.decodeIfPresentFirst(String.self, forKeys: [.deviceAlias, .deviceAliasSnake])
        creditsTotal = try container.decodeIfPresentFirst(Int.self, forKeys: [.creditsTotal, .creditsTotalSnake])
        creditsRemaining = try container.decodeIfPresentFirst(Int.self, forKeys: [.creditsRemaining, .creditsRemainingSnake])
        validUntil = try container.decodeIfPresentFirst(Date.self, forKeys: [.validUntil, .validUntilSnake])
        allowedModelIDs = try container.decodeIfPresentFirst([String].self, forKeys: [.allowedModelIDs, .allowedModelIDsConverted, .allowedModelIDsSnake, .allowedModelIDsSnakeBuggy])
        activationFingerprint = try container.decodeIfPresentFirst(String.self, forKeys: [.activationFingerprint, .activationFingerprintSnake])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activationCode, forKey: .activationCode)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(platform, forKey: .platform)
        try container.encodeIfPresent(deviceAlias, forKey: .deviceAlias)
        try container.encodeIfPresent(creditsTotal, forKey: .creditsTotal)
        try container.encodeIfPresent(creditsRemaining, forKey: .creditsRemaining)
        try container.encodeIfPresent(validUntil, forKey: .validUntil)
        try container.encodeIfPresent(allowedModelIDs, forKey: .allowedModelIDs)
        try container.encodeIfPresent(activationFingerprint, forKey: .activationFingerprint)
    }
}

nonisolated struct RelayPurchaseSubmissionResponse: Codable, Equatable, Sendable {
    var status: RelayAccountStatusResponse
}
