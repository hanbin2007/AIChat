import Foundation

typealias ModelID = String

/// Pure projection of the server account+key+catalog, decoupled from wire Codable types.
struct RelaySnapshot: Codable, Equatable {
    var accountID: UUID
    var accountState: RelayAccountState
    var source: RelayAccessSource
    var keyValue: String
    var keyState: RelayKeyState
    var creditBalance: Int
    var creditExpiresAt: Date?
    var availableModels: [ModelID]
    var rates: [ModelID: ModelRate]
}

struct ModelRate: Codable, Equatable {
    var inputCreditsPerMillion: Int
    var outputCreditsPerMillion: Int
    var searchSurchargeCredits: Int
}

// MARK: - Decision (the single consumption outlet, spec §4)

struct EntitlementDecision: Equatable {
    enum Capability: Equatable {
        case ready
        case readOnly(LockReason)
        case bootstrapping
    }
    var capability: Capability
    var availableModels: [ModelID]
    var credits: CreditView?
    var cta: ActionableCTA?
}

enum LockReason: Equatable {
    case platformNotConfigured
    case noAccount
    case revoked
    case expired
    case exhausted
    case offlineGraceElapsed
}

struct CreditView: Equatable {
    var balance: Int            // effective = server balance - localSpend
    var expiresAt: Date?
}

enum ActionableCTA: Equatable {
    case configurePlatform
    case activate
    case reenterCode
    case renew
    case goOnline
}

// MARK: - State (persisted, spec §5)

struct OfflineCode: Codable, Equatable {
    var raw: String
    var issuedAt: Date
}

struct PairingToken: Codable, Equatable {
    var token: String
    var issuedAt: Date
}

enum PendingBootstrap: Codable, Equatable {
    case offlineCode(OfflineCode)
    case pairedToken(PairingToken)

    var issuedAt: Date {
        switch self {
        case let .offlineCode(c): return c.issuedAt
        case let .pairedToken(t): return t.issuedAt
        }
    }
}

enum RelayHardFailure: String, Codable, Equatable {
    case revoked
    case paused
    case accountMissing
}

struct EntitlementState: Codable, Equatable {
    var account: RelaySnapshot?
    var lastVerifiedAt: Date?
    var localSpend: Int
    var pending: PendingBootstrap?
    var lastError: RelayHardFailure?
    var schemaVersion: Int

    init(
        account: RelaySnapshot? = nil,
        lastVerifiedAt: Date? = nil,
        localSpend: Int = 0,
        pending: PendingBootstrap? = nil,
        lastError: RelayHardFailure? = nil,
        schemaVersion: Int = 1
    ) {
        self.account = account
        self.lastVerifiedAt = lastVerifiedAt
        self.localSpend = localSpend
        self.pending = pending
        self.lastError = lastError
        self.schemaVersion = schemaVersion
    }
}

// MARK: - Events (spec §5)

enum EntitlementEvent {
    case relayRefreshed(RelaySnapshot, now: Date)
    case relayRefreshFailed(hard: RelayHardFailure?, now: Date)  // hard != nil for 401/revoke
    case offlineCodeEntered(OfflineCode)
    case pairedTokenReceived(PairingToken)
    case exchangeSucceeded(RelaySnapshot, now: Date)
    case purchaseApplied(RelaySnapshot, now: Date)
    case messageConsumed(cost: Int)
    case signedOut
    case keyRevoked
}
