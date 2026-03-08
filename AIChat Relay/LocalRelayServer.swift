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
            await eventHandler(.didReceiveRequest(path: path, remoteAddress: remoteAddress))

            if request.method == "GET", path == "/health" {
                try await sendJSON(
                    statusCode: 200,
                    payload: ["ok": true],
                    on: connection
                )
                return
            }

            guard request.method == "POST", path == "/v1/chat/stream" else {
                try await sendJSON(
                    statusCode: 404,
                    payload: RelayErrorEnvelope(message: "Not found."),
                    on: connection
                )
                return
            }

            let configuration = await configurationProvider()
            guard configuration.geminiAPIKey.isEmpty == false else {
                try await sendJSON(
                    statusCode: RelayHTTPError.missingConfiguration("Gemini API key is missing.").statusCode,
                    payload: RelayErrorEnvelope(message: "Gemini API key is missing."),
                    on: connection
                )
                return
            }

            guard configuration.relayBearerToken.isEmpty == false else {
                try await sendJSON(
                    statusCode: RelayHTTPError.missingConfiguration("Relay bearer token is missing.").statusCode,
                    payload: RelayErrorEnvelope(message: "Relay bearer token is missing."),
                    on: connection
                )
                return
            }

            let authorization = request.headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard authorization == "Bearer \(configuration.relayBearerToken)" else {
                try await sendJSON(
                    statusCode: RelayHTTPError.unauthorized.statusCode,
                    payload: RelayErrorEnvelope(message: RelayHTTPError.unauthorized.message),
                    on: connection
                )
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let relayRequest: RelayChatRequest
            do {
                relayRequest = try decoder.decode(RelayChatRequest.self, from: request.body)
            } catch {
                try await sendJSON(
                    statusCode: RelayHTTPError.badRequest("Invalid JSON body.").statusCode,
                    payload: RelayErrorEnvelope(message: "Invalid JSON body."),
                    on: connection
                )
                return
            }

            let streamState = StreamOpenState()

            do {
                try await relayBridge.streamChat(
                    relayRequest: relayRequest,
                    apiKey: configuration.geminiAPIKey,
                    onOpen: {
                        streamState.didOpen = true
                        try await self.sendSSEHeaders(on: connection)
                    },
                    onEvent: { event in
                        try await self.send(event.data(), on: connection)
                    }
                )
            } catch let error as RelayHTTPError {
                if streamState.didOpen {
                    try? await send(RelayOutboundEvent.error(error.message).data(), on: connection)
                } else {
                    try await sendJSON(
                        statusCode: error.statusCode,
                        payload: RelayErrorEnvelope(message: error.message),
                        on: connection
                    )
                }
            } catch {
                let relayError = RelayHTTPError.internalError(error.localizedDescription)
                if streamState.didOpen {
                    try? await send(RelayOutboundEvent.error(relayError.message).data(), on: connection)
                } else {
                    try await sendJSON(
                        statusCode: relayError.statusCode,
                        payload: RelayErrorEnvelope(message: relayError.message),
                        on: connection
                    )
                }
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
            """
            HTTP/1.1 200 OK\r
            Content-Type: text/event-stream; charset=utf-8\r
            Cache-Control: no-cache, no-transform\r
            Connection: close\r
            \r
            """

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
            """
            HTTP/1.1 \(statusCode) \(reasonPhrase(for: statusCode))\r
            Content-Type: application/json; charset=utf-8\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r
            """

        var data = Data(header.utf8)
        data.append(body)
        try await send(data, on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
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
