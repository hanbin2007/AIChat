//
//  RelayRequestBuilder.swift
//  AIChat Watch App
//
//  Builds `URLRequest` instances for the Next.js relay. Centralises URL
//  composition, header injection, and JSON encoding so the API client
//  stays focused on framing and decoding.
//

import Foundation

struct RelayRequestContext: Sendable {
    var baseURL: URL
    var deviceID: String
    var bearerToken: String?
    var allowsInsecureTLS: Bool

    var allowedHost: String? {
        baseURL.host?.lowercased()
    }
}

enum RelayRequestBuilderError: Error, Equatable {
    case invalidURL
}

struct RelayRequestBuilder {
    let context: RelayRequestContext

    func build(
        endpoint: RelayEndpoint,
        body: Data? = nil,
        conversationID: UUID? = nil,
        requestID: String? = nil,
        accept: String? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint.path, relativeTo: context.baseURL) else {
            throw RelayRequestBuilderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.timeoutInterval = endpoint.isStreaming ? 600 : 60

        if endpoint.method != "GET", let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        } else if endpoint.isStreaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        if let token = context.bearerToken, token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if context.deviceID.isEmpty == false {
            request.setValue(context.deviceID, forHTTPHeaderField: "X-Aichat-Device-Id")
        }

        if let conversationID {
            request.setValue(conversationID.uuidString, forHTTPHeaderField: "X-Aichat-Conversation-Id")
        }

        let resolvedRequestID = requestID ?? UUID().uuidString
        request.setValue(resolvedRequestID, forHTTPHeaderField: "X-Request-Id")

        return request
    }

    func encode<T: Encodable>(_ value: T) throws -> Data {
        try RelayJSON.makeEncoder().encode(value)
    }
}
