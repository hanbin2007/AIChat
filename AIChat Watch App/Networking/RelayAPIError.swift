//
//  RelayClientError.swift
//  AIChat Watch App
//
//  Typed errors emitted by the new `RelayAPIClient` actor. Maps the
//  relay's uniform `{ "message": String }` envelope plus the HTTP
//  status codes we treat specially: 402 payment required, 429 rate
//  limited, 499 client closed, 502/503 upstream/server.
//
//  The legacy enum `RelayAPIError` in `Services/RelayAIClient.swift`
//  is preserved for now so `RelayAccountService` and the old factory
//  keep compiling. Once those are migrated to the new actor, the
//  legacy enum will be removed and this file may be renamed back to
//  `RelayAPIError.swift`.
//

import Foundation

nonisolated enum RelayClientError: LocalizedError, Equatable, Sendable {
    case missingConfiguration
    case invalidResponse
    case badRequest(message: String)
    case unauthorized(message: String?)
    case paymentRequired(message: String?)
    case notFound(message: String?)
    case rateLimited(retryAfter: TimeInterval?, message: String?)
    case clientClosed
    case upstream(status: Int, message: String?)
    case server(status: Int, message: String?)
    case remote(message: String)
    case incompleteResponse
    case truncated
    case transport(message: String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return L10n.tr("error.relay.missing_configuration")
        case .invalidResponse:
            return L10n.tr("error.relay.invalid_response")
        case .badRequest(let message):
            return message
        case .unauthorized(let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .paymentRequired(let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .notFound(let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .rateLimited(_, let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .clientClosed:
            return L10n.tr("error.relay.invalid_response")
        case .upstream(_, let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .server(_, let message):
            return message ?? L10n.tr("error.relay.invalid_response")
        case .remote(let message):
            return message
        case .incompleteResponse:
            return L10n.tr("error.reply.incomplete")
        case .truncated:
            return L10n.tr("error.reply.truncated")
        case .transport(let message):
            return message
        }
    }

    /// Map an `HTTPURLResponse` status + body + headers to a typed error.
    /// Used by every unary endpoint and by the streaming session when
    /// the initial response status is non-2xx.
    static func from(status: Int, body: Data, headers: [AnyHashable: Any]) -> RelayClientError {
        let envelopeMessage = decodeEnvelope(body)
        switch status {
        case 200...299:
            return .invalidResponse
        case 400:
            return .badRequest(message: envelopeMessage ?? "Bad request")
        case 401:
            return .unauthorized(message: envelopeMessage)
        case 402:
            return .paymentRequired(message: envelopeMessage)
        case 404:
            return .notFound(message: envelopeMessage)
        case 429:
            return .rateLimited(retryAfter: parseRetryAfter(headers: headers), message: envelopeMessage)
        case 499:
            return .clientClosed
        case 500...599 where status == 502 || status == 503:
            return .upstream(status: status, message: envelopeMessage)
        default:
            return .server(status: status, message: envelopeMessage)
        }
    }

    private static func decodeEnvelope(_ data: Data) -> String? {
        guard data.isEmpty == false else { return nil }
        if let envelope = try? JSONDecoder().decode(RelayClientErrorEnvelope.self, from: data) {
            let trimmed = envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyTrimmed
    }

    private static func parseRetryAfter(headers: [AnyHashable: Any]) -> TimeInterval? {
        for (key, value) in headers {
            if let stringKey = key as? String, stringKey.caseInsensitiveCompare("Retry-After") == .orderedSame {
                if let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let seconds = Double(raw) {
                    return seconds
                }
            }
        }
        return nil
    }
}

nonisolated struct RelayClientErrorEnvelope: Codable, Sendable {
    var message: String
}
