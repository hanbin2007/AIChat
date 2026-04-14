//
//  LocalRelayServer.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import Network

private struct RelayCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

actor LocalRelayServer {
    private let configurationProvider: @Sendable () async -> RelayRuntimeConfiguration
    private let eventHandler: @Sendable (RelayServerEvent) async -> Void
    private let relayBridge: GeminiRelayBridge
    private let billingStore: RelayBillingStore
    private let queue = DispatchQueue(label: "hanbin.aichat.relay.server")

    private var listener: NWListener?

    init(
        configurationProvider: @escaping @Sendable () async -> RelayRuntimeConfiguration,
        eventHandler: @escaping @Sendable (RelayServerEvent) async -> Void,
        relayBridge: GeminiRelayBridge = GeminiRelayBridge(),
        billingStore: RelayBillingStore = RelayBillingStore()
    ) {
        self.configurationProvider = configurationProvider
        self.eventHandler = eventHandler
        self.relayBridge = relayBridge
        self.billingStore = billingStore
    }

    func start() async throws {
        guard listener == nil else {
            return
        }

        let configuration = await configurationProvider()
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw RelayHTTPError.badRequest("Choose a valid TCP port.")
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        if configuration.allowNetworkClients {
            listener = try NWListener(using: parameters, on: port)
        } else {
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            listener = try NWListener(using: parameters)
        }

        self.listener = listener

        try await withCheckedThrowingContinuation { continuation in
            let resolutionState = ContinuationState()

            listener.stateUpdateHandler = { [weak listener] listenerState in
                guard listener != nil else {
                    return
                }

                Task { [weak self] in
                    await self?.handleListenerState(listenerState)
                }

                switch listenerState {
                case .ready:
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume()
                case .failed(let error):
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume(throwing: RelayHTTPError.internalError("Relay start was cancelled."))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handleIncomingConnection(connection)
                }
            }

            listener.start(queue: queue)
        }
    }

    func stop() async {
        listener?.cancel()
        listener = nil
    }

    private func handleListenerState(_ state: NWListener.State) async {
        switch state {
        case .ready:
            let configuration = await configurationProvider()
            await eventHandler(.didStart(port: configuration.port))
            await emitLifecycleLog(
                level: .success,
                message: "Relay is listening on port \(configuration.port)."
            )
        case .failed(let error):
            listener = nil
            await eventHandler(.listenerFailed(message: error.localizedDescription))
        case .cancelled:
            listener = nil
            await eventHandler(.didStop)
        default:
            break
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) async {
        do {
            try await prepare(connection)
            defer { connection.cancel() }

            let request = try await readRequest(from: connection)
            let path = request.path
            let method = request.method
            let remoteAddress = remoteAddressDescription(for: connection)
            let configuration = await configurationProvider()
            await eventHandler(
                .didReceiveRequest(
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    context: nil
                )
            )
            await logDebugRequestIfNeeded(
                request,
                path: path,
                remoteAddress: remoteAddress,
                configuration: configuration
            )

            if request.method == "GET", path == "/health" {
                try await sendJSON(
                    statusCode: 200,
                    payload: ["ok": true],
                    on: connection
                )
                await markSuccessfulRequest(path: path, method: method, remoteAddress: remoteAddress)
                return
            }

            if request.method == "GET", path == "/v1/billing/catalog" {
                try await sendJSON(
                    statusCode: 200,
                    payload: await billingStore.catalogResponse(),
                    on: connection
                )
                await markSuccessfulRequest(path: path, method: method, remoteAddress: remoteAddress)
                return
            }

            if request.method == "GET", path == "/v1/account/status" {
                let statusClientKey = bearerToken(from: request.headers)
                let statusClientContext: RelayAuthorizedKeyContext? = if let statusClientKey {
                    await billingStore.authorize(clientKey: statusClientKey)
                } else {
                    nil
                }
                try await sendJSON(
                    statusCode: 200,
                    payload: await billingStore.accountStatus(
                        clientKey: statusClientKey,
                        deviceID: request.headers["x-aichat-device-id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    on: connection
                )
                var resolvedContext: RelayActorContext?
                if let statusClientContext {
                    resolvedContext = await billingStore.metadata(for: statusClientContext, modelID: nil)
                }
                await markSuccessfulRequest(
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    context: resolvedContext
                )
                return
            }

            guard request.method == "POST" else {
                try await sendFailureResponse(
                    statusCode: 404,
                    message: "Not found.",
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            do {
                if try await handleBillingRouteIfNeeded(
                    request: request,
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                ) {
                    return
                }
            } catch let error as RelayHTTPError {
                try await sendFailureResponse(
                    statusCode: error.statusCode,
                    message: error.message,
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            } catch {
                let relayError = RelayHTTPError.internalError(error.localizedDescription)
                try await sendFailureResponse(
                    statusCode: relayError.statusCode,
                    message: relayError.message,
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            guard path == "/v1/chat/stream" || path == "/v1/audio/transcribe" || path == "/v1/memory/extract" else {
                try await sendFailureResponse(
                    statusCode: 404,
                    message: "Not found.",
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            guard configuration.geminiAPIKey.isEmpty == false else {
                try await sendFailureResponse(
                    statusCode: RelayHTTPError.missingConfiguration("Gemini API key is missing.").statusCode,
                    message: "Gemini API key is missing.",
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            guard configuration.relayBearerToken.isEmpty == false else {
                try await sendFailureResponse(
                    statusCode: RelayHTTPError.missingConfiguration("Relay bearer token is missing.").statusCode,
                    message: "Relay bearer token is missing.",
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            let authorization = request.headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let adminAuthorized = authorization == "Bearer \(configuration.relayBearerToken)"
            let clientAuthorized: RelayAuthorizedKeyContext? = if let clientKey = bearerToken(from: request.headers) {
                await billingStore.authorize(clientKey: clientKey)
            } else {
                nil
            }
            guard adminAuthorized || clientAuthorized != nil else {
                try await sendFailureResponse(
                    statusCode: RelayHTTPError.unauthorized.statusCode,
                    message: RelayHTTPError.unauthorized.message,
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = Self.snakeCaseKeyDecodingStrategy

            switch path {
            case "/v1/chat/stream":
                let relayRequest: RelayChatRequest
                do {
                    relayRequest = try decoder.decode(RelayChatRequest.self, from: request.body)
                } catch {
                    let earlyContext: RelayActorContext?
                    if let clientAuthorized {
                        earlyContext = await billingStore.metadata(for: clientAuthorized, modelID: nil)
                    } else {
                        earlyContext = nil
                    }
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: earlyContext,
                        on: connection
                    )
                    return
                }

                let streamState = StreamOpenState()
                let resolvedModelID = relayRequest.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? relayRequest.model!
                    : "gemini-3-flash-preview"
                let usageBox = UsageSnapshotBox()
                let actorContext: RelayActorContext?
                if let clientAuthorized {
                    actorContext = await billingStore.metadata(for: clientAuthorized, modelID: resolvedModelID)
                } else {
                    actorContext = nil
                }

                do {
                    let reservationEstimate: RelayUsageReservationEstimate?
                    if let clientAuthorized {
                        let estimatedInputTokens = try await relayBridge.estimateChatInputTokens(
                            relayRequest: relayRequest,
                            apiKey: configuration.geminiAPIKey,
                            debugLog: debugLogger(enabled: configuration.debugLoggingEnabled)
                        )
                        let reservedOutputTokens = relayRequest.maxOutputTokens.flatMap { $0 > 0 ? $0 : nil }
                            ?? defaultMaxOutputTokens(for: resolvedModelID)
                        let reservedCredits = await billingStore.creditsForUsage(
                            modelID: resolvedModelID,
                            inputTokens: estimatedInputTokens,
                            outputTokens: reservedOutputTokens,
                            searchCount: relayRequest.usesGoogleSearch == true ? 1 : 0,
                            inputTokensOver200k: estimatedInputTokens > 200_000,
                            usesAudioInput: false
                        )
                        try await billingStore.ensureCreditAllowance(
                            accountID: clientAuthorized.accountID,
                            requiredCredits: reservedCredits
                        )
                        reservationEstimate = RelayUsageReservationEstimate(
                            inputTokens: estimatedInputTokens,
                            outputTokens: reservedOutputTokens,
                            reservedCredits: reservedCredits
                        )
                    } else {
                        reservationEstimate = nil
                    }

                    try await relayBridge.streamChat(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled, context: actorContext),
                        onOpen: {
                            streamState.didOpen = true
                            try await self.sendSSEHeaders(on: connection)
                        },
                        onEvent: { event in
                            try await self.send(event.data(), on: connection)
                        },
                        onUsage: { usage in
                            usageBox.value = usage
                        }
                    )
                    try? await finishResponse(on: connection)
                    await recordUsageIfNeeded(
                        clientContext: clientAuthorized,
                        reservation: reservationEstimate,
                        endpoint: path,
                        modelID: resolvedModelID,
                        usage: usageBox.value,
                        searchCount: relayRequest.usesGoogleSearch == true ? 1 : 0,
                        usesAudioInput: false
                    )
                    await markSuccessfulRequest(
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: actorContext
                    )
                } catch let error as RelayHTTPError {
                    await markFailedRequest(
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        statusCode: error.statusCode,
                        message: error.message,
                        context: actorContext
                    )
                    if streamState.didOpen {
                        try? await send(RelayOutboundEvent.error(error.message).data(), on: connection)
                        try? await finishResponse(on: connection)
                    } else {
                        try await sendJSON(
                            statusCode: error.statusCode,
                            payload: RelayErrorEnvelope(message: error.message),
                            on: connection
                        )
                    }
                } catch {
                    let relayError = RelayHTTPError.internalError(error.localizedDescription)
                    await markFailedRequest(
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        statusCode: relayError.statusCode,
                        message: relayError.message,
                        context: actorContext
                    )
                    if streamState.didOpen {
                        try? await send(RelayOutboundEvent.error(relayError.message).data(), on: connection)
                        try? await finishResponse(on: connection)
                    } else {
                        try await sendJSON(
                            statusCode: relayError.statusCode,
                            payload: RelayErrorEnvelope(message: relayError.message),
                            on: connection
                        )
                    }
                }
            case "/v1/audio/transcribe":
                let relayRequest: RelayTranscriptionRequest
                do {
                    relayRequest = try decoder.decode(RelayTranscriptionRequest.self, from: request.body)
                } catch {
                    let earlyContext: RelayActorContext?
                    if let clientAuthorized {
                        earlyContext = await billingStore.metadata(for: clientAuthorized, modelID: nil)
                    } else {
                        earlyContext = nil
                    }
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: earlyContext,
                        on: connection
                    )
                    return
                }

                let transcriptionModelID = relayRequest.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? relayRequest.model!
                    : "gemini-3-flash-preview"
                let transcriptionContext: RelayActorContext?
                if let clientAuthorized {
                    transcriptionContext = await billingStore.metadata(for: clientAuthorized, modelID: transcriptionModelID)
                } else {
                    transcriptionContext = nil
                }

                do {
                    let reservationEstimate: RelayUsageReservationEstimate?
                    if let clientAuthorized {
                        let estimatedInputTokens = try await relayBridge.estimateTranscriptionInputTokens(
                            relayRequest: relayRequest,
                            apiKey: configuration.geminiAPIKey,
                            debugLog: debugLogger(enabled: configuration.debugLoggingEnabled, context: transcriptionContext)
                        )
                        let reservedCredits = await billingStore.creditsForUsage(
                            modelID: relayRequest.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? relayRequest.model!
                                : "gemini-3-flash-preview",
                            inputTokens: estimatedInputTokens,
                            outputTokens: 5_120,
                            searchCount: 0,
                            inputTokensOver200k: estimatedInputTokens > 200_000,
                            usesAudioInput: true
                        )
                        try await billingStore.ensureCreditAllowance(
                            accountID: clientAuthorized.accountID,
                            requiredCredits: reservedCredits
                        )
                        reservationEstimate = RelayUsageReservationEstimate(
                            inputTokens: estimatedInputTokens,
                            outputTokens: 5_120,
                            reservedCredits: reservedCredits
                        )
                    } else {
                        reservationEstimate = nil
                    }

                    let (relayResponse, upstreamUsage) = try await relayBridge.transcribeAudio(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled, context: transcriptionContext)
                    )

                    try await sendJSON(
                        statusCode: 200,
                        payload: relayResponse,
                        on: connection
                    )
                    await logDebugClientResponseIfNeeded(
                        relayResponse,
                        path: path,
                        statusCode: 200,
                        remoteAddress: remoteAddress,
                        context: transcriptionContext,
                        enabled: configuration.debugLoggingEnabled
                    )
                    await recordUsageIfNeeded(
                        clientContext: clientAuthorized,
                        reservation: reservationEstimate,
                        endpoint: path,
                        modelID: transcriptionModelID,
                        usage: upstreamUsage,
                        searchCount: 0,
                        usesAudioInput: true
                    )
                    await markSuccessfulRequest(
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: transcriptionContext
                    )
                } catch let error as RelayHTTPError {
                    try await sendFailureResponse(
                        statusCode: error.statusCode,
                        message: error.message,
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: transcriptionContext,
                        on: connection
                    )
                } catch {
                    let relayError = RelayHTTPError.internalError(error.localizedDescription)
                    try await sendFailureResponse(
                        statusCode: relayError.statusCode,
                        message: relayError.message,
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: transcriptionContext,
                        on: connection
                    )
                }
            case "/v1/memory/extract":
                let relayRequest: RelayMemoryExtractionRequest
                do {
                    relayRequest = try decoder.decode(RelayMemoryExtractionRequest.self, from: request.body)
                } catch {
                    let earlyContext: RelayActorContext?
                    if let clientAuthorized {
                        earlyContext = await billingStore.metadata(for: clientAuthorized, modelID: nil)
                    } else {
                        earlyContext = nil
                    }
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: earlyContext,
                        on: connection
                    )
                    return
                }

                let memoryModelID = relayRequest.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? relayRequest.model!
                    : "gemini-3-flash-preview"
                let memoryContext: RelayActorContext?
                if let clientAuthorized {
                    memoryContext = await billingStore.metadata(for: clientAuthorized, modelID: memoryModelID)
                } else {
                    memoryContext = nil
                }

                do {
                    let reservationEstimate: RelayUsageReservationEstimate?
                    if let clientAuthorized {
                        let estimatedInputTokens = try await relayBridge.estimateMemoryInputTokens(
                            relayRequest: relayRequest,
                            apiKey: configuration.geminiAPIKey,
                            debugLog: debugLogger(enabled: configuration.debugLoggingEnabled, context: memoryContext)
                        )
                        let reservedCredits = await billingStore.creditsForUsage(
                            modelID: relayRequest.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                                ? relayRequest.model!
                                : "gemini-3-flash-preview",
                            inputTokens: estimatedInputTokens,
                            outputTokens: 4_096,
                            searchCount: 0,
                            inputTokensOver200k: estimatedInputTokens > 200_000,
                            usesAudioInput: false
                        )
                        try await billingStore.ensureCreditAllowance(
                            accountID: clientAuthorized.accountID,
                            requiredCredits: reservedCredits
                        )
                        reservationEstimate = RelayUsageReservationEstimate(
                            inputTokens: estimatedInputTokens,
                            outputTokens: 4_096,
                            reservedCredits: reservedCredits
                        )
                    } else {
                        reservationEstimate = nil
                    }

                    let (relayResponse, upstreamUsage) = try await relayBridge.extractMemory(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled, context: memoryContext)
                    )

                    try await sendJSON(
                        statusCode: 200,
                        payload: relayResponse,
                        on: connection
                    )
                    await logDebugClientResponseIfNeeded(
                        relayResponse,
                        path: path,
                        statusCode: 200,
                        remoteAddress: remoteAddress,
                        context: memoryContext,
                        enabled: configuration.debugLoggingEnabled
                    )
                    await recordUsageIfNeeded(
                        clientContext: clientAuthorized,
                        reservation: reservationEstimate,
                        endpoint: path,
                        modelID: memoryModelID,
                        usage: upstreamUsage,
                        searchCount: 0,
                        usesAudioInput: false
                    )
                    await markSuccessfulRequest(
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: memoryContext
                    )
                } catch let error as RelayHTTPError {
                    try await sendFailureResponse(
                        statusCode: error.statusCode,
                        message: error.message,
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: memoryContext,
                        on: connection
                    )
                } catch {
                    let relayError = RelayHTTPError.internalError(error.localizedDescription)
                    try await sendFailureResponse(
                        statusCode: relayError.statusCode,
                        message: relayError.message,
                        path: path,
                        method: method,
                        remoteAddress: remoteAddress,
                        context: memoryContext,
                        on: connection
                    )
                }
            default:
                try await sendFailureResponse(
                    statusCode: 404,
                    message: "Not found.",
                    path: path,
                    method: method,
                    remoteAddress: remoteAddress,
                    on: connection
                )
            }
        } catch {
            await emitLifecycleLog(
                level: .warning,
                message: "Connection closed: \(error.localizedDescription)"
            )
            connection.cancel()
        }
    }

    private func handleBillingRouteIfNeeded(
        request: HTTPRequest,
        path: String,
        method: String?,
        remoteAddress: String?,
        on connection: NWConnection
    ) async throws -> Bool {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = Self.snakeCaseKeyDecodingStrategy
        decoder.dateDecodingStrategy = .iso8601

        switch path {
        case "/v1/activation/bootstrap":
            let payload = try decoder.decode(RelayActivationBootstrapRequest.self, from: request.body)
            let response = try await billingStore.bootstrap(request: payload)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/billing/purchase/prepare":
            let payload = try decoder.decode(RelayPurchasePrepareRequest.self, from: request.body)
            let response = try await billingStore.purchasePrepare(
                request: payload,
                currentKey: bearerToken(from: request.headers)
            )
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/billing/purchase/submit":
            let payload = try decoder.decode(RelayPurchaseSubmitRequest.self, from: request.body)
            let response = try await billingStore.submitPurchase(payload)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/billing/restore":
            let payload = try decoder.decode(RelayRestorePurchasesRequest.self, from: request.body)
            let response = try await billingStore.restorePurchases(payload)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/account/pairing-token":
            guard let key = bearerToken(from: request.headers) else {
                throw RelayHTTPError.unauthorized
            }
            let response = try await billingStore.pairingToken(forClientKey: key)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/account/join-paired":
            let payload = try decoder.decode(RelayJoinPairedRequest.self, from: request.body)
            let response = try await billingStore.joinPaired(payload)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        case "/v1/offline/exchange":
            let payload = try decoder.decode(RelayOfflineExchangeRequest.self, from: request.body)
            let response = try await billingStore.exchangeOffline(payload)
            try await sendJSON(statusCode: 200, payload: response, on: connection)
        default:
            return false
        }

        let billingContextKey = bearerToken(from: request.headers)
        var billingContext: RelayActorContext?
        if let billingContextKey,
           let authorized = await billingStore.authorize(clientKey: billingContextKey) {
            billingContext = await billingStore.metadata(for: authorized, modelID: nil)
        }
        await markSuccessfulRequest(
            path: path,
            method: method,
            remoteAddress: remoteAddress,
            context: billingContext
        )
        return true
    }

    private func prepare(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let resolutionState = ContinuationState()

            connection.stateUpdateHandler = { connectionState in
                switch connectionState {
                case .ready:
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume()
                case .failed(let error):
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard resolutionState.didResolve == false else { return }
                    resolutionState.didResolve = true
                    continuation.resume(throwing: RelayHTTPError.internalError("Connection was cancelled."))
                default:
                    break
                }
            }

            connection.start(queue: queue)
        }
    }

    private func readRequest(from connection: NWConnection) async throws -> HTTPRequest {
        var buffer = Data()
        let delimiter = Data("\r\n\r\n".utf8)

        while true {
            if let headerRange = buffer.range(of: delimiter) {
                let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
                guard let headerText = String(data: headerData, encoding: .utf8) else {
                    throw RelayHTTPError.badRequest("Invalid HTTP headers.")
                }

                let lines = headerText.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else {
                    throw RelayHTTPError.badRequest("Invalid HTTP request line.")
                }

                let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
                guard requestParts.count >= 2 else {
                    throw RelayHTTPError.badRequest("Invalid HTTP request line.")
                }

                var headers: [String: String] = [:]
                for line in lines.dropFirst() where line.isEmpty == false {
                    guard let separator = line.firstIndex(of: ":") else {
                        continue
                    }

                    let key = line[..<separator].lowercased()
                    let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    headers[key] = value
                }

                let contentLength = Int(headers["content-length"] ?? "0") ?? 0
                var body = Data(buffer[headerRange.upperBound...])

                while body.count < contentLength {
                    let nextChunk = try await receive(on: connection, maximumLength: 65_536)
                    guard nextChunk.isEmpty == false else {
                        throw RelayHTTPError.badRequest("Unexpected end of request body.")
                    }
                    body.append(nextChunk)
                }

                if body.count > contentLength {
                    body = Data(body.prefix(contentLength))
                }

                let target = String(requestParts[1])
                let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target

                return HTTPRequest(
                    method: String(requestParts[0]).uppercased(),
                    path: path,
                    headers: headers,
                    body: body
                )
            }

            let chunk = try await receive(on: connection, maximumLength: 65_536)
            guard chunk.isEmpty == false else {
                throw RelayHTTPError.badRequest("Incomplete HTTP request.")
            }

            buffer.append(chunk)

            if buffer.count > 16_777_216 {
                throw RelayHTTPError.badRequest("Request body is too large.")
            }
        }
    }

    private func receive(on connection: NWConnection, maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data, data.isEmpty == false {
                    continuation.resume(returning: data)
                    return
                }

                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }

                continuation.resume(returning: Data())
            }
        }
    }

    private func sendSSEHeaders(on connection: NWConnection) async throws {
        let header =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/event-stream; charset=utf-8\r\n" +
            "Cache-Control: no-cache, no-transform\r\n" +
            "Connection: close\r\n" +
            "\r\n"

        try await send(Data(header.utf8), on: connection)
    }

    /// A key decoding strategy that converts snake_case JSON keys to camelCase
    /// while correctly preserving common abbreviations (ID, URL, URI, API, USD).
    /// Swift's built-in `.convertFromSnakeCase` lowercases abbreviations
    /// (e.g. `device_id` → `deviceId` instead of `deviceID`), which causes
    /// decoding failures for properties like `deviceID`, `accountID`, etc.
    private static let snakeCaseKeyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .custom { codingPath in
        guard let lastKey = codingPath.last else {
            return RelayCodingKey(stringValue: "")
        }
        let key = lastKey.stringValue
        guard key.contains("_") else {
            return RelayCodingKey(stringValue: key)
        }
        let abbreviations: Set<String> = ["id", "url", "uri", "api", "usd"]
        let segments = key.split(separator: "_").map(String.init)
        guard let first = segments.first else {
            return RelayCodingKey(stringValue: key)
        }
        let convertedFirst = abbreviations.contains(first) ? first.uppercased() : first
        let rest = segments.dropFirst().map { segment in
            abbreviations.contains(segment) ? segment.uppercased() : segment.capitalized
        }
        return RelayCodingKey(stringValue: convertedFirst + rest.joined())
    }

    private func sendJSON<T: Encodable>(
        statusCode: Int,
        payload: T,
        on connection: NWConnection
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(payload)
        let header =
            "HTTP/1.1 \(statusCode) \(reasonPhrase(for: statusCode))\r\n" +
            "Content-Type: application/json; charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n"

        var data = Data(header.utf8)
        data.append(body)
        try await send(data, on: connection, isComplete: true)
    }

    private func sendFailureResponse(
        statusCode: Int,
        message: String,
        path: String,
        method: String? = nil,
        remoteAddress: String?,
        context: RelayActorContext? = nil,
        on connection: NWConnection
    ) async throws {
        await markFailedRequest(
            path: path,
            method: method,
            remoteAddress: remoteAddress,
            statusCode: statusCode,
            message: message,
            context: context
        )

        try await sendJSON(
            statusCode: statusCode,
            payload: RelayErrorEnvelope(message: message),
            on: connection
        )
    }

    private func finishResponse(on connection: NWConnection) async throws {
        try await send(Data(), on: connection, isComplete: true)
    }

    private func send(
        _ data: Data,
        on connection: NWConnection,
        isComplete: Bool = false
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: isComplete,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 401:
            return "Unauthorized"
        case 402:
            return "Payment Required"
        case 404:
            return "Not Found"
        case 502:
            return "Bad Gateway"
        case 503:
            return "Service Unavailable"
        default:
            return "Error"
        }
    }

    private func remoteAddressDescription(for connection: NWConnection) -> String? {
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint

        if case let .hostPort(host, port) = endpoint {
            return "\(host):\(port.rawValue)"
        }

        return nil
    }

    private func markSuccessfulRequest(
        path: String,
        method: String? = nil,
        remoteAddress: String?,
        context: RelayActorContext? = nil
    ) async {
        await eventHandler(
            .didCompleteRequest(
                path: path,
                method: method,
                remoteAddress: remoteAddress,
                context: context
            )
        )
    }

    private func markFailedRequest(
        path: String,
        method: String? = nil,
        remoteAddress: String?,
        statusCode: Int,
        message: String,
        context: RelayActorContext? = nil
    ) async {
        await eventHandler(
            .didFailRequest(
                path: path,
                method: method,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                message: message,
                context: context
            )
        )
    }

    /// Helper for emitting lifecycle/system log events without an actor
    /// context attached. All other call sites should use the full
    /// `.log(...)` case directly so the dashboard can offer rich filtering.
    private func emitLifecycleLog(
        level: RelayLogLevel,
        message: String,
        path: String? = nil,
        method: String? = nil,
        remoteAddress: String? = nil,
        statusCode: Int? = nil,
        category: RelayLogCategory = .lifecycle,
        context: RelayActorContext? = nil
    ) async {
        await eventHandler(
            .log(
                level: level,
                message: message,
                category: category,
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                context: context
            )
        )
    }

    private func debugLogger(
        enabled: Bool,
        context: RelayActorContext? = nil
    ) -> (@Sendable (RelayDebugEvent) async -> Void)? {
        guard enabled else {
            return nil
        }

        return { [eventHandler] event in
            await eventHandler(.debug(event.withContext(context)))
        }
    }

    private func logDebugRequestIfNeeded(
        _ request: HTTPRequest,
        path: String,
        remoteAddress: String?,
        configuration: RelayRuntimeConfiguration,
        context: RelayActorContext? = nil
    ) async {
        guard configuration.debugLoggingEnabled else {
            return
        }

        let location = remoteAddress.map { " from \($0)" } ?? ""
        await eventHandler(
            .debug(
                RelayDebugEvent(
                    source: .client,
                    kind: .request,
                    title: "Client Request",
                    summary: "\(request.method) \(path)\(location)",
                    method: request.method,
                    path: path,
                    address: remoteAddress,
                    statusCode: nil,
                    body: RelayDebugFormatter.httpRequest(
                        method: request.method,
                        url: path,
                        headers: request.headers,
                        body: request.body
                    ),
                    context: context
                )
            )
        )
    }

    private func logDebugClientResponseIfNeeded<T: Encodable>(
        _ payload: T,
        path: String,
        statusCode: Int,
        remoteAddress: String?,
        context: RelayActorContext? = nil,
        enabled: Bool
    ) async {
        guard enabled else {
            return
        }

        let encoder = JSONEncoder()
        let body = try? encoder.encode(payload)

        await eventHandler(
            .debug(
                RelayDebugEvent(
                    source: .relay,
                    kind: .response,
                    title: "Relay Response",
                    summary: "\(statusCode) \(path)",
                    method: nil,
                    path: path,
                    address: remoteAddress,
                    statusCode: statusCode,
                    body: RelayDebugFormatter.httpResponse(
                        statusCode: statusCode,
                        headers: ["content-type": "application/json; charset=utf-8"],
                        body: body
                    ),
                    context: context
                )
            )
        )
    }

    private func recordUsageIfNeeded(
        clientContext: RelayAuthorizedKeyContext?,
        reservation: RelayUsageReservationEstimate?,
        endpoint: String,
        modelID: String,
        usage: RelayUpstreamUsage?,
        searchCount: Int,
        usesAudioInput: Bool
    ) async {
        guard let clientContext else {
            return
        }

        let effectiveUsage: RelayUpstreamUsage
        if let usage {
            effectiveUsage = usage
        } else if let reservation {
            effectiveUsage = RelayUpstreamUsage(
                inputTokens: reservation.inputTokens,
                outputTokens: reservation.outputTokens,
                totalTokens: reservation.inputTokens + reservation.outputTokens,
                thoughtTokens: 0
            )
        } else {
            return
        }

        let settledCredits = await billingStore.creditsForUsage(
            modelID: modelID,
            inputTokens: effectiveUsage.inputTokens,
            outputTokens: effectiveUsage.outputTokens,
            searchCount: searchCount,
            inputTokensOver200k: effectiveUsage.inputTokensOver200k,
            usesAudioInput: usesAudioInput
        )
        let reservedCredits = reservation?.reservedCredits ?? settledCredits

        do {
            try await billingStore.recordUsage(
                accountID: clientContext.accountID,
                deviceID: clientContext.deviceID,
                keyID: clientContext.keyID,
                endpoint: endpoint,
                modelID: modelID,
                inputTokens: effectiveUsage.inputTokens,
                outputTokens: effectiveUsage.outputTokens,
                searchCount: searchCount,
                reservedCredits: reservedCredits,
                settledCredits: settledCredits
            )
        } catch {
            await eventHandler(
                .log(
                    level: .warning,
                    message: "Usage settlement failed for \(endpoint): \(error.localizedDescription)",
                    category: .usage,
                    method: nil,
                    path: endpoint,
                    remoteAddress: nil,
                    statusCode: nil,
                    context: await billingStore.metadata(
                        for: clientContext,
                        modelID: modelID
                    )
                )
            )
        }
    }
}

private struct RelayUsageReservationEstimate: Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var reservedCredits: Int
}

private struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private func bearerToken(from headers: [String: String]) -> String? {
    let authorization = headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard authorization.hasPrefix("Bearer ") else {
        return nil
    }

    let value = String(authorization.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func defaultMaxOutputTokens(for modelID: String) -> Int {
    if modelID.hasPrefix("gemini-3") || modelID.hasPrefix("gemini-2.5") {
        return 65_536
    }

    return 8_192
}

private final class ContinuationState: @unchecked Sendable {
    var didResolve = false
}

private final class StreamOpenState: @unchecked Sendable {
    var didOpen = false
}

private final class UsageSnapshotBox: @unchecked Sendable {
    var value: RelayUpstreamUsage?
}
