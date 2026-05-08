//
//  RelayAPIClient.swift
//  AIChat Watch App
//
//  Typed actor-based client for every endpoint exposed by the in-repo
//  Next.js relay (`relay/src/app/api/v1/*`). Streaming is delegated to
//  `ChatStreamSession`. Unary endpoints use `URLSession.data(for:)` and
//  the shared error mapping in `RelayClientError.from(...)`.
//
//  Billing/activation request and response shapes reuse the canonical
//  Codable types in `Shared Licensing/RelayBillingContracts.swift` so
//  the Watch, iOS, and macOS apps share one wire contract.
//

import Foundation

actor RelayAPIClient {
    private let context: RelayRequestContext
    private let unarySession: URLSession
    private let builder: RelayRequestBuilder
    private let decoder: JSONDecoder

    init(context: RelayRequestContext, unarySession: URLSession? = nil) {
        self.context = context
        self.unarySession = unarySession ?? RelayURLSessionFactory.makeUnarySession(context: context)
        self.builder = RelayRequestBuilder(context: context)
        self.decoder = RelayJSON.makeDecoder()
    }

    // MARK: Streaming

    nonisolated func streamChat(
        _ payload: RelayStreamRequest,
        conversationID: UUID
    ) -> AsyncThrowingStream<RelayChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body = try builder.encode(payload)
                    let request = try builder.build(
                        endpoint: .chatStream,
                        body: body,
                        conversationID: conversationID
                    )
                    let session = ChatStreamSession(context: context)
                    let stream = session.stream(
                        request: request,
                        allowsInsecureTLS: context.allowsInsecureTLS,
                        allowedHost: context.allowedHost
                    )
                    for try await event in stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Unary endpoints

    func transcribeAudio(_ payload: RelayTranscribeRequest) async throws -> RelayTranscribeResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .audioTranscribe, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayTranscribeResponse.self, from: data)
    }

    func extractMemory(_ payload: RelayMemoryExtractRequest) async throws -> RelayMemoryExtractResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .memoryExtract, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayMemoryExtractResponse.self, from: data)
    }

    func accountStatus() async throws -> RelayAccountStatusResponse {
        let request = try builder.build(endpoint: .accountStatus)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayAccountStatusResponse.self, from: data)
    }

    func billingCatalog() async throws -> RelayCatalogResponse {
        let request = try builder.build(endpoint: .billingCatalog)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayCatalogResponse.self, from: data)
    }

    func bootstrapActivation(_ payload: RelayActivationBootstrapRequest) async throws -> RelayAccountStatusResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .activationBootstrap, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayAccountStatusResponse.self, from: data)
    }

    func preparePurchase(_ payload: RelayPurchasePrepareRequest) async throws -> RelayPurchasePrepareResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .purchasePrepare, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayPurchasePrepareResponse.self, from: data)
    }

    func submitPurchase(_ payload: RelayPurchaseSubmitRequest) async throws -> RelayPurchaseSubmissionResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .purchaseSubmit, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayPurchaseSubmissionResponse.self, from: data)
    }

    func restorePurchases(_ payload: RelayRestorePurchasesRequest) async throws -> RelayPurchaseSubmissionResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .purchaseRestore, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayPurchaseSubmissionResponse.self, from: data)
    }

    func issuePairingToken() async throws -> RelayPairingTokenResponse {
        let request = try builder.build(endpoint: .pairingTokenIssue, body: Data("{}".utf8))
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayPairingTokenResponse.self, from: data)
    }

    func joinPaired(_ payload: RelayJoinPairedRequest) async throws -> RelayAccountStatusResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .joinPaired, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayAccountStatusResponse.self, from: data)
    }

    func exchangeOffline(_ payload: RelayOfflineExchangeRequest) async throws -> RelayAccountStatusResponse {
        let body = try builder.encode(payload)
        let request = try builder.build(endpoint: .offlineExchange, body: body)
        let data = try await performUnary(request: request)
        return try decoder.decode(RelayAccountStatusResponse.self, from: data)
    }

    func health() async throws -> RelayHealthResponse {
        let request = try builder.build(endpoint: .health)
        let data = try await performUnary(request: request)
        return (try? decoder.decode(RelayHealthResponse.self, from: data)) ?? RelayHealthResponse(status: nil, version: nil)
    }

    // MARK: Internal

    private func performUnary(request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await unarySession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RelayClientError.invalidResponse
            }
            if (200...299).contains(http.statusCode) == false {
                throw RelayClientError.from(
                    status: http.statusCode,
                    body: data,
                    headers: http.allHeaderFields
                )
            }
            return data
        } catch let error as RelayClientError {
            throw error
        } catch {
            throw RelayClientError.transport(message: error.localizedDescription)
        }
    }
}
