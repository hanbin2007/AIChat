import Foundation

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
}

nonisolated struct RelayDeviceSummary: Codable, Equatable, Hashable, Sendable {
    var deviceID: String
    var platform: RelayDevicePlatform
    var alias: String?
    var note: String?
    var keyID: UUID?
    var lastSeenAt: Date?
}

nonisolated struct RelayKeySummary: Codable, Equatable, Hashable, Sendable {
    var keyID: UUID
    var keyValue: String
    var state: RelayKeyState
    var source: RelayAccessSource
    var note: String?
    var issuedAt: Date
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
