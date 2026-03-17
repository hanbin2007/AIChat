//
//  LocalRelayServer.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Foundation
import Network

actor LocalRelayServer {
    private let configurationProvider: @Sendable () async -> RelayRuntimeConfiguration
    private let eventHandler: @Sendable (RelayServerEvent) async -> Void
    private let relayBridge: GeminiRelayBridge
    private let queue = DispatchQueue(label: "hanbin.aichat.relay.server")

    private var listener: NWListener?

    init(
        configurationProvider: @escaping @Sendable () async -> RelayRuntimeConfiguration,
        eventHandler: @escaping @Sendable (RelayServerEvent) async -> Void,
        relayBridge: GeminiRelayBridge = GeminiRelayBridge()
    ) {
        self.configurationProvider = configurationProvider
        self.eventHandler = eventHandler
        self.relayBridge = relayBridge
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
            await eventHandler(.log(level: .success, message: "Relay is listening on port \(configuration.port)."))
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
            let remoteAddress = remoteAddressDescription(for: connection)
            let configuration = await configurationProvider()
            await eventHandler(.didReceiveRequest(path: path, remoteAddress: remoteAddress))
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
                await markSuccessfulRequest(path: path, remoteAddress: remoteAddress)
                return
            }

            guard request.method == "POST" else {
                try await sendFailureResponse(
                    statusCode: 404,
                    message: "Not found.",
                    path: path,
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
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            let authorization = request.headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard authorization == "Bearer \(configuration.relayBearerToken)" else {
                try await sendFailureResponse(
                    statusCode: RelayHTTPError.unauthorized.statusCode,
                    message: RelayHTTPError.unauthorized.message,
                    path: path,
                    remoteAddress: remoteAddress,
                    on: connection
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            switch path {
            case "/v1/chat/stream":
                let relayRequest: RelayChatRequest
                do {
                    relayRequest = try decoder.decode(RelayChatRequest.self, from: request.body)
                } catch {
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                    return
                }

                let streamState = StreamOpenState()

                do {
                    try await relayBridge.streamChat(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled),
                        onOpen: {
                            streamState.didOpen = true
                            try await self.sendSSEHeaders(on: connection)
                        },
                        onEvent: { event in
                            try await self.send(event.data(), on: connection)
                        }
                    )
                    try? await finishResponse(on: connection)
                    await markSuccessfulRequest(path: path, remoteAddress: remoteAddress)
                } catch let error as RelayHTTPError {
                    await markFailedRequest(
                        path: path,
                        remoteAddress: remoteAddress,
                        statusCode: error.statusCode,
                        message: error.message
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
                        remoteAddress: remoteAddress,
                        statusCode: relayError.statusCode,
                        message: relayError.message
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
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                    return
                }

                do {
                    let relayResponse = try await relayBridge.transcribeAudio(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled)
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
                        enabled: configuration.debugLoggingEnabled
                    )
                    await markSuccessfulRequest(path: path, remoteAddress: remoteAddress)
                } catch let error as RelayHTTPError {
                    try await sendFailureResponse(
                        statusCode: error.statusCode,
                        message: error.message,
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                } catch {
                    let relayError = RelayHTTPError.internalError(error.localizedDescription)
                    try await sendFailureResponse(
                        statusCode: relayError.statusCode,
                        message: relayError.message,
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                }
            case "/v1/memory/extract":
                let relayRequest: RelayMemoryExtractionRequest
                do {
                    relayRequest = try decoder.decode(RelayMemoryExtractionRequest.self, from: request.body)
                } catch {
                    try await sendFailureResponse(
                        statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                        message: "Invalid JSON body.",
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                    return
                }

                do {
                    let relayResponse = try await relayBridge.extractMemory(
                        relayRequest: relayRequest,
                        apiKey: configuration.geminiAPIKey,
                        debugLog: debugLogger(enabled: configuration.debugLoggingEnabled)
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
                        enabled: configuration.debugLoggingEnabled
                    )
                    await markSuccessfulRequest(path: path, remoteAddress: remoteAddress)
                } catch let error as RelayHTTPError {
                    try await sendFailureResponse(
                        statusCode: error.statusCode,
                        message: error.message,
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                } catch {
                    let relayError = RelayHTTPError.internalError(error.localizedDescription)
                    try await sendFailureResponse(
                        statusCode: relayError.statusCode,
                        message: relayError.message,
                        path: path,
                        remoteAddress: remoteAddress,
                        on: connection
                    )
                }
            default:
                try await sendFailureResponse(
                    statusCode: 404,
                    message: "Not found.",
                    path: path,
                    remoteAddress: remoteAddress,
                    on: connection
                )
            }
        } catch {
            await eventHandler(.log(level: .warning, message: "Connection closed: \(error.localizedDescription)"))
            connection.cancel()
        }
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

    private func sendJSON<T: Encodable>(
        statusCode: Int,
        payload: T,
        on connection: NWConnection
    ) async throws {
        let encoder = JSONEncoder()
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
        remoteAddress: String?,
        on connection: NWConnection
    ) async throws {
        await markFailedRequest(
            path: path,
            remoteAddress: remoteAddress,
            statusCode: statusCode,
            message: message
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
        remoteAddress: String?
    ) async {
        await eventHandler(.didCompleteRequest(path: path, remoteAddress: remoteAddress))
    }

    private func markFailedRequest(
        path: String,
        remoteAddress: String?,
        statusCode: Int,
        message: String
    ) async {
        await eventHandler(
            .didFailRequest(
                path: path,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                message: message
            )
        )
    }

    private func debugLogger(
        enabled: Bool
    ) -> (@Sendable (RelayDebugEvent) async -> Void)? {
        guard enabled else {
            return nil
        }

        return { [eventHandler] event in
            await eventHandler(.debug(event))
        }
    }

    private func logDebugRequestIfNeeded(
        _ request: HTTPRequest,
        path: String,
        remoteAddress: String?,
        configuration: RelayRuntimeConfiguration
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
                )
                )
            )
        )
    }

    private func logDebugClientResponseIfNeeded<T: Encodable>(
        _ payload: T,
        path: String,
        statusCode: Int,
        remoteAddress: String?,
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
                )
                )
            )
        )
    }
}

private struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

private final class ContinuationState: @unchecked Sendable {
    var didResolve = false
}

private final class StreamOpenState: @unchecked Sendable {
    var didOpen = false
}
