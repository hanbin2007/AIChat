import Foundation

struct RelayAccountService {
    let configuration: AppConfiguration
    let deviceIdentity: WatchDeviceIdentity
    let repository: RelayAccessRepository
    var session: URLSession = .shared

    func refreshOrBootstrapStatus(forceBootstrap: Bool = false) async throws -> RelayAccountStatusResponse? {
        guard configuration.backendMode == .relay else {
            return nil
        }

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

        let response: RelayAccountStatusResponse = try await performJSONRequest(
            to: configuration.relayBootstrapURL,
            method: "POST",
            body: payload
        )
        try await repository.saveStatus(response)
        return response
    }

    func fetchAccountStatusIfPossible() async throws -> RelayAccountStatusResponse? {
        guard configuration.backendMode == .relay,
              configuration.relayAccountStatusURL != nil
        else {
            return nil
        }

        guard let bearerToken = configuration.resolvedRelayBearerToken else {
            return nil
        }

        return try await performJSONRequest(
            to: configuration.relayAccountStatusURL,
            method: "GET",
            bearerToken: bearerToken,
            deviceIDHeader: deviceIdentity.rawIdentifier
        )
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

        let response: RelayAccountStatusResponse = try await performJSONRequest(
            to: url,
            method: "POST",
            body: payload
        )
        try await repository.saveStatus(response)
        return response
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
            bearerToken: configuration.resolvedRelayBearerToken
        )
    }

    func submitPurchase(transaction: RelaySubmittedTransaction) async throws -> RelayAccountStatusResponse {
        let payload = RelayPurchaseSubmitRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            transaction: transaction
        )
        let response: RelayPurchaseSubmissionResponse = try await performJSONRequest(
            to: configuration.relayPurchaseSubmitURL,
            method: "POST",
            body: payload
        )
        try await repository.saveStatus(response.status)
        return response.status
    }

    func restorePurchases(transactions: [RelaySubmittedTransaction]) async throws -> RelayAccountStatusResponse {
        let payload = RelayRestorePurchasesRequest(
            deviceID: deviceIdentity.rawIdentifier,
            platform: Self.currentPlatform,
            transactions: transactions
        )
        let response: RelayPurchaseSubmissionResponse = try await performJSONRequest(
            to: configuration.relayPurchaseRestoreURL,
            method: "POST",
            body: payload
        )
        try await repository.saveStatus(response.status)
        return response.status
    }

    func requestPairingToken() async throws -> RelayPairingTokenResponse {
        guard let bearerToken = configuration.resolvedRelayBearerToken else {
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
        let response: RelayAccountStatusResponse = try await performJSONRequest(
            to: configuration.relayJoinPairedURL,
            method: "POST",
            body: payload
        )
        try await repository.saveStatus(response)
        return response
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
            throw relayClientError(from: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
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
}
