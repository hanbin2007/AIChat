//
//  RelayEndpoint.swift
//  AIChat Watch App
//
//  Path + HTTP method enumeration for the Next.js relay's v1 surface.
//  Keeps URL composition out of `RelayAPIClient` so it stays focused on
//  framing and decoding.
//

import Foundation

enum RelayEndpoint: Sendable {
    case chatStream
    case audioTranscribe
    case memoryExtract
    case accountStatus
    case billingCatalog
    case activationBootstrap
    case purchasePrepare
    case purchaseSubmit
    case purchaseRestore
    case pairingTokenIssue
    case joinPaired
    case offlineExchange
    case health

    var path: String {
        switch self {
        case .chatStream: return "v1/chat/stream"
        case .audioTranscribe: return "v1/audio/transcribe"
        case .memoryExtract: return "v1/memory/extract"
        case .accountStatus: return "v1/account/status"
        case .billingCatalog: return "v1/billing/catalog"
        case .activationBootstrap: return "v1/activation/bootstrap"
        case .purchasePrepare: return "v1/billing/purchase/prepare"
        case .purchaseSubmit: return "v1/billing/purchase/submit"
        case .purchaseRestore: return "v1/billing/restore"
        case .pairingTokenIssue: return "v1/account/pairing-token"
        case .joinPaired: return "v1/account/join-paired"
        case .offlineExchange: return "v1/offline/exchange"
        case .health: return "api/health"
        }
    }

    var method: String {
        switch self {
        case .accountStatus, .billingCatalog, .health:
            return "GET"
        default:
            return "POST"
        }
    }

    /// Endpoints that produce SSE streams instead of a single JSON body.
    var isStreaming: Bool {
        if case .chatStream = self { return true }
        return false
    }

    /// Endpoints reachable without a per-device `rk_*` bearer (still send
    /// admin token if present).
    var requiresAuth: Bool {
        switch self {
        case .activationBootstrap, .joinPaired, .offlineExchange, .billingCatalog, .health:
            return false
        default:
            return true
        }
    }
}
