//
//  RelayTLSPinningDelegate.swift
//  AIChat Watch App
//
//  Trusts the configured relay host even when its certificate is
//  self-signed. Only honoured when `AppConfiguration.relayAllowsInsecureTLS`
//  is `true`. Default builds use ATS-validated TLS via the system trust
//  store and never construct this delegate.
//

import Foundation

final class RelayTLSPinningDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let allowedHost: String

    init(allowedHost: String) {
        self.allowedHost = allowedHost.lowercased()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == allowedHost,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

enum RelayURLSessionFactory {
    /// Returns the shared session unless self-signed TLS is enabled, in
    /// which case a delegate-backed session that pins the configured
    /// host is created. Streaming sessions need their own delegate
    /// instance and should call `makeStreamingSession(delegate:)` directly.
    static func makeUnarySession(context: RelayRequestContext) -> URLSession {
        guard context.allowsInsecureTLS, let host = context.allowedHost, host.isEmpty == false else {
            return .shared
        }
        let delegate = RelayTLSPinningDelegate(allowedHost: host)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    /// Build a fresh session for one streaming task. Caller must invalidate
    /// it once the stream completes.
    static func makeStreamingSession(delegate: URLSessionDataDelegate) -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}
