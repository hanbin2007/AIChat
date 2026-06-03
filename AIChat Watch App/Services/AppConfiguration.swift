//
//  AppConfiguration.swift
//  AIChat Watch App
//
//  Relay-only runtime configuration. Direct-Gemini fields and the
//  `AIBackendMode` switch were removed in the rewrite; the watch
//  always proxies through the in-repo Next.js relay.
//

import Foundation

nonisolated struct AppConfiguration: Equatable {
    /// Default model the relay should use when a conversation has no
    /// per-conversation override. The relay rewrites bare model names
    /// to the upstream provider's id; the watch only carries it
    /// through.
    let geminiModel: String
    let geminiTranscriptionModel: String
    let relayBaseURL: URL?
    let relayBearerToken: String?
    let relayStreamPath: String
    let relayAllowsInsecureTLS: Bool
    let appGroupIdentifier: String?
    let iCloudContainerIdentifier: String?

    init(
        geminiModel: String,
        geminiTranscriptionModel: String,
        relayBaseURL: URL?,
        relayBearerToken: String?,
        relayStreamPath: String = "v1/chat/stream",
        relayAllowsInsecureTLS: Bool = false,
        appGroupIdentifier: String?,
        iCloudContainerIdentifier: String? = nil
    ) {
        self.geminiModel = geminiModel
        self.geminiTranscriptionModel = geminiTranscriptionModel
        self.relayBaseURL = relayBaseURL
        self.relayBearerToken = relayBearerToken
        self.relayStreamPath = relayStreamPath
        self.relayAllowsInsecureTLS = relayAllowsInsecureTLS
        self.appGroupIdentifier = appGroupIdentifier
        self.iCloudContainerIdentifier = iCloudContainerIdentifier?.nonEmptyTrimmed
    }

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        let environment = processInfo.environment
        let geminiModel = value(for: "GEMINI_MODEL", bundle: bundle, environment: environment) ?? "gemini-3-flash-preview"
        let geminiTranscriptionModel = value(
            for: "GEMINI_TRANSCRIPTION_MODEL",
            bundle: bundle,
            environment: environment
        ) ?? "gemini-3-flash-preview"
        let relayBaseURL = value(for: "AI_RELAY_BASE_URL", bundle: bundle, environment: environment)
            .flatMap(URL.init(string:))
        let relayBearerToken = value(for: "AI_RELAY_BEARER_TOKEN", bundle: bundle, environment: environment)
        let relayStreamPath = value(for: "AI_RELAY_STREAM_PATH", bundle: bundle, environment: environment) ?? "v1/chat/stream"
        let relayAllowsInsecureTLS = boolValue(
            for: "AI_RELAY_ALLOW_INSECURE_TLS",
            bundle: bundle,
            environment: environment
        )
        let appGroupIdentifier = value(for: "APP_GROUP_IDENTIFIER", bundle: bundle, environment: environment)
        let iCloudContainerIdentifier = value(
            for: "ICLOUD_CONTAINER_IDENTIFIER",
            bundle: bundle,
            environment: environment
        )
        return AppConfiguration(
            geminiModel: geminiModel,
            geminiTranscriptionModel: geminiTranscriptionModel,
            relayBaseURL: relayBaseURL,
            relayBearerToken: relayBearerToken,
            relayStreamPath: relayStreamPath,
            relayAllowsInsecureTLS: relayAllowsInsecureTLS,
            appGroupIdentifier: appGroupIdentifier,
            iCloudContainerIdentifier: iCloudContainerIdentifier
        )
    }

    var isAIConfigured: Bool { relayConfigurationIssue == nil }

    var relayStreamURL: URL? { relayURL(path: relayStreamPath) }
    var relayBootstrapURL: URL? { relayURL(path: "v1/activation/bootstrap") }
    var relayCatalogURL: URL? { relayURL(path: "v1/billing/catalog") }
    var relayAccountStatusURL: URL? { relayURL(path: "v1/account/status") }
    var relayPurchasePrepareURL: URL? { relayURL(path: "v1/billing/purchase/prepare") }
    var relayPurchaseSubmitURL: URL? { relayURL(path: "v1/billing/purchase/submit") }
    var relayPurchaseRestoreURL: URL? { relayURL(path: "v1/billing/restore") }
    var relayPairingTokenURL: URL? { relayURL(path: "v1/account/pairing-token") }
    var relayJoinPairedURL: URL? { relayURL(path: "v1/account/join-paired") }
    var relayOfflineExchangeURL: URL? { relayURL(path: "v1/offline/exchange") }
    var relayTranscriptionURL: URL? { relayURL(path: "v1/audio/transcribe") }
    var relayMemoryExtractURL: URL? { relayURL(path: "v1/memory/extract") }

    /// The bearer token the watch sends on every request. Prefers the
    /// device-specific `rk_*` key persisted in `UserDefaults` (written
    /// by `RelayKeyStore.set(...)` after a successful bootstrap or
    /// pairing flow); falls back to the xcconfig-supplied bearer for
    /// the legacy Mac relay where there's no per-user key.
    var resolvedRelayBearerToken: String? {
        if let key = RelayKeyStore.load(appGroupIdentifier: appGroupIdentifier) {
            return key
        }
        return relayBearerToken
    }

    private func relayURL(path: String) -> URL? {
        guard let baseURL = relayBaseURL,
              baseURL.scheme?.isEmpty == false,
              baseURL.host()?.isEmpty == false
        else { return nil }
        return baseURL.appending(path: path)
    }

    private var hasValidRelayBaseURL: Bool {
        guard let relayBaseURL else { return false }
        return relayBaseURL.scheme?.isEmpty == false && relayBaseURL.host()?.isEmpty == false
    }

    private var relayConfigurationIssue: String? {
        guard relayBaseURL != nil else { return L10n.tr("configuration.relay.missing_base_url") }
        guard hasValidRelayBaseURL else { return L10n.tr("configuration.relay.invalid_base_url") }
        guard resolvedRelayBearerToken != nil else { return L10n.tr("configuration.relay.missing_bearer") }
        return nil
    }

    private static func value(
        for key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        environment[key]?.nonEmptyTrimmed ??
        (bundle.object(forInfoDictionaryKey: key) as? String)?.nonEmptyTrimmed
    }

    private static func boolValue(
        for key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> Bool {
        guard let rawValue = value(for: key, bundle: bundle, environment: environment)?.lowercased() else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(rawValue)
    }

}

/// Lightweight UserDefaults-backed cache for the device's relay
/// bearer key. Activation / pairing flows write here so a synchronous
/// `AppConfiguration.resolvedRelayBearerToken` can read it during
/// `RelayAPIClient` construction without going through the
/// async `BillingPersistence` actor.
nonisolated enum RelayKeyStore {
    private static let userDefaultsKey = "AIChat.relay.bearerKey.v2"

    static func load(appGroupIdentifier: String?) -> String? {
        let defaults = makeDefaults(appGroupIdentifier: appGroupIdentifier)
        return defaults.string(forKey: userDefaultsKey)?.nonEmptyTrimmed
    }

    static func set(_ key: String?, appGroupIdentifier: String?) {
        let defaults = makeDefaults(appGroupIdentifier: appGroupIdentifier)
        if let key = key?.nonEmptyTrimmed {
            defaults.set(key, forKey: userDefaultsKey)
        } else {
            defaults.removeObject(forKey: userDefaultsKey)
        }
    }

    private static func makeDefaults(appGroupIdentifier: String?) -> UserDefaults {
        if let appGroupIdentifier,
           let suite = UserDefaults(suiteName: appGroupIdentifier) {
            return suite
        }
        return .standard
    }
}
