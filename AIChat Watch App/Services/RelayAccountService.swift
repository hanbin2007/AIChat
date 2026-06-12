import Foundation

/// Typed signals raised by the relay account/billing endpoints that callers
/// need to react to distinctly. Kept separate from `RelayAPIError` (which is
/// shared with the streaming client) so the billing layer can branch on a
/// revoked/expired key without string-matching.
enum RelayAccountServiceError: LocalizedError, Equatable {
    /// HTTP 401 from the relay: the stored `rk_` key is revoked or expired.
    /// Callers should clear the stored key and re-bootstrap.
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L10n.tr("error.relay.invalid_response")
        }
    }
}

struct RelayAccountService {
    let configuration: AppConfiguration
    let deviceIdentity: WatchDeviceIdentity
    let repository: RelayAccessRepository
    var session: URLSession = .shared

    func refreshOrBootstrapStatus(forceBootstrap: Bool = false) async throws -> RelayAccountStatusResponse? {
        if forceBootstrap == false,
           let status = try await fetchAccountStatusIfPossible() {
            try await repository.saveStatus(status)
            return status
        }

        let payload = RelayActivationBootstrapRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            deviceAlias: Self.currentDeviceAlias()
        )

        do {
            let response: RelayAccountStatusResponse = try await performJSONRequest(
                to: configuration.relayBootstrapURL,
                method: "POST",
                body: payload
            )
            try await repository.saveStatus(response)
            return response
        } catch RelayAPIError.emptyResponse {
            if let status = try await fetchAccountStatusIfPossible() {
                try await repository.saveStatus(status)
                return status
            }
            return nil
        }
    }

    func fetchAccountStatusIfPossible() async throws -> RelayAccountStatusResponse? {
        guard configuration.relayAccountStatusURL != nil else {
            return nil
        }

        guard let bearerToken = await storedBearerToken() else {
            return nil
        }

        do {
            return try await performJSONRequest(
                to: configuration.relayAccountStatusURL,
                method: "GET",
                bearerToken: bearerToken,
                deviceIDHeader: deviceIdentity.rawIdentifier
            )
        } catch RelayAPIError.emptyResponse {
            return nil
        }
    }

    func exchangeOfflineActivation(
        code: String,
        state: OfflineActivationState
    ) async throws -> RelayAccountStatusResponse {
        guard let url = configuration.relayOfflineExchangeURL else {
            throw RelayAPIError.missingConfiguration
        }

        let totalCredits = state.license.creditLimit
        let payload = RelayOfflineExchangeRequest(
            activationCode: code,
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            deviceAlias: Self.currentDeviceAlias(),
            creditsTotal: totalCredits,
            creditsRemaining: state.remainingCredits ?? totalCredits,
            validUntil: state.license.validUntil,
            allowedModelIDs: state.license.allowedModelIDs?.sorted(),
            activationFingerprint: state.activationCodeFingerprint
        )

        do {
            let response: RelayAccountStatusResponse = try await performJSONRequest(
                to: url,
                method: "POST",
                body: payload
            )
            try await repository.saveStatus(response)
            return response
        } catch RelayAPIError.emptyResponse {
            if let status = try await fetchAccountStatusIfPossible() {
                try await repository.saveStatus(status)
                return status
            }
            throw RelayAPIError.emptyResponse
        }
    }

    func fetchCatalog() async throws -> RelayCatalogResponse {
        try await performJSONRequest(
            to: configuration.relayCatalogURL,
            method: "GET"
        )
    }

    func preparePurchase() async throws -> RelayPurchasePrepareResponse {
        let payload = RelayPurchasePrepareRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform
        )
        return try await performJSONRequest(
            to: configuration.relayPurchasePrepareURL,
            method: "POST",
            body: payload,
            bearerToken: await storedBearerToken()
        )
    }

    func submitPurchase(transaction: RelaySubmittedTransaction) async throws -> RelayAccountStatusResponse {
        let payload = RelayPurchaseSubmitRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            transaction: transaction
        )
        do {
            let response: RelayPurchaseSubmissionResponse = try await performJSONRequest(
                to: configuration.relayPurchaseSubmitURL,
                method: "POST",
                body: payload,
                bearerToken: await storedBearerToken()
            )
            try await repository.saveStatus(response.status)
            return response.status
        } catch RelayAPIError.emptyResponse {
            if let status = try await fetchAccountStatusIfPossible() {
                try await repository.saveStatus(status)
                return status
            }
            throw RelayAPIError.emptyResponse
        }
    }

    func restorePurchases(transactions: [RelaySubmittedTransaction]) async throws -> RelayAccountStatusResponse {
        let payload = RelayRestorePurchasesRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            transactions: transactions
        )
        do {
            let response: RelayPurchaseSubmissionResponse = try await performJSONRequest(
                to: configuration.relayPurchaseRestoreURL,
                method: "POST",
                body: payload,
                bearerToken: await storedBearerToken()
            )
            try await repository.saveStatus(response.status)
            return response.status
        } catch RelayAPIError.emptyResponse {
            if let status = try await fetchAccountStatusIfPossible() {
                try await repository.saveStatus(status)
                return status
            }
            throw RelayAPIError.emptyResponse
        }
    }

    func requestPairingToken() async throws -> RelayPairingTokenResponse {
        guard let bearerToken = await storedBearerToken() else {
            throw RelayAPIError.missingConfiguration
        }

        return try await performJSONRequest(
            to: configuration.relayPairingTokenURL,
            method: "POST",
            bearerToken: bearerToken
        )
    }

    func joinPaired(pairingToken: String) async throws -> RelayAccountStatusResponse {
        let payload = RelayJoinPairedRequest(
            pairingToken: pairingToken,
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            deviceAlias: Self.currentDeviceAlias()
        )
        do {
            let response: RelayAccountStatusResponse = try await performJSONRequest(
                to: configuration.relayJoinPairedURL,
                method: "POST",
                body: payload
            )
            try await repository.saveStatus(response)
            return response
        } catch RelayAPIError.emptyResponse {
            if let status = try await fetchAccountStatusIfPossible() {
                try await repository.saveStatus(status)
                return status
            }
            throw RelayAPIError.emptyResponse
        }
    }

    private func storedBearerToken() async -> String? {
        await repository.storedRelayKey()
    }

    private func performJSONRequest<T: Decodable, Body: Encodable>(
        to url: URL?,
        method: String,
        body: Body?,
        bearerToken: String? = nil,
        deviceIDHeader: String? = nil
    ) async throws -> T {
        guard let url else {
            throw RelayAPIError.missingConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let deviceIDHeader {
            request.setValue(deviceIDHeader, forHTTPHeaderField: "x-aichat-device-id")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        }

        let relaySession = makeRelayURLSession(
            configuration: configuration,
            fallback: session
        )
        let (data, response) = try await relaySession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // 401 means the stored key was revoked/expired. Surface a typed
            // signal so callers can clear the local key, rather than collapsing
            // every non-2xx into a generic error.
            if httpResponse.statusCode == 401 {
                throw RelayAccountServiceError.unauthorized
            }
            throw relayClientError(from: data)
        }

        guard responseBodyContainsJSON(data) else {
            throw RelayAPIError.emptyResponse
        }

        return try decodeRelayResponse(T.self, from: data)
    }

    private func performJSONRequest<T: Decodable>(
        to url: URL?,
        method: String,
        bearerToken: String? = nil,
        deviceIDHeader: String? = nil
    ) async throws -> T {
        try await performJSONRequest(
            to: url,
            method: method,
            body: Optional<String>.none,
            bearerToken: bearerToken,
            deviceIDHeader: deviceIDHeader
        )
    }

    private nonisolated static var currentPlatform: RelayDevicePlatform {
        #if os(watchOS)
        return .watch
        #elseif os(iOS)
        return .iPhone
        #elseif os(macOS)
        return .mac
        #else
        return .unknown
        #endif
    }

    private nonisolated static func currentDeviceAlias() -> String {
        #if os(watchOS)
        return "Apple Watch"
        #elseif os(iOS)
        return "iPhone"
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Device"
        #endif
    }

    private func responseBodyContainsJSON(_ data: Data) -> Bool {
        guard data.isEmpty == false else {
            return false
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return true
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && trimmed != "null"
    }

    private func decodeRelayResponse<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.applyRelayDateDecoding()

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            guard let normalizedData = normalizeRelayResponseData(data) else {
                throw RelayAPIError.invalidResponse
            }

            let fallbackDecoder = JSONDecoder()
            fallbackDecoder.applyRelayDateDecoding()
            do {
                return try fallbackDecoder.decode(T.self, from: normalizedData)
            } catch {
                throw RelayAPIError.invalidResponse
            }
        }
    }

    private func normalizeRelayResponseData(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let normalizedObject = normalizeRelayResponseObject(object)
        return try? JSONSerialization.data(withJSONObject: normalizedObject)
    }

    private func normalizeRelayResponseObject(_ object: Any) -> Any {
        switch object {
        case let dictionary as [String: Any]:
            var normalized: [String: Any] = [:]
            normalized.reserveCapacity(dictionary.count)
            for (key, value) in dictionary {
                normalized[normalizedRelayResponseKey(key)] = normalizeRelayResponseObject(value)
            }
            return normalized
        case let array as [Any]:
            return array.map(normalizeRelayResponseObject)
        default:
            return object
        }
    }

    private func normalizedRelayResponseKey(_ key: String) -> String {
        guard key.contains("_") else {
            return key
        }

        let uppercaseSegments: Set<String> = ["id", "url", "uri", "api", "usd"]
        let segments = key.split(separator: "_").map(String.init)
        guard let firstSegment = segments.first else {
            return key
        }

        let normalizedFirst = uppercaseSegments.contains(firstSegment) ? firstSegment.uppercased() : firstSegment
        let normalizedTail = segments.dropFirst().map { segment in
            if uppercaseSegments.contains(segment) {
                return segment.uppercased()
            }

            guard let firstCharacter = segment.first else {
                return segment
            }

            return String(firstCharacter).uppercased() + segment.dropFirst()
        }

        return ([normalizedFirst] + normalizedTail).joined()
    }
}
