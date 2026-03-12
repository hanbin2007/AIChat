//
//  AppConfiguration.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

nonisolated enum AIBackendMode: String, Codable, Equatable {
    case direct
    case relay

    var displayName: String {
        switch self {
        case .direct:
            return L10n.tr("backend.direct")
        case .relay:
            return L10n.tr("backend.relay")
        }
    }
}

nonisolated struct AppConfiguration: Equatable {
    let backendMode: AIBackendMode
    let geminiAPIKey: String?
    let geminiModel: String
    let geminiTranscriptionModel: String
    let relayBaseURL: URL?
    let relayBearerToken: String?
    let relayStreamPath: String
    let relayAllowsInsecureTLS: Bool
    let appGroupIdentifier: String?

    init(
        backendMode: AIBackendMode,
        geminiAPIKey: String?,
        geminiModel: String,
        geminiTranscriptionModel: String,
        relayBaseURL: URL?,
        relayBearerToken: String?,
        relayStreamPath: String,
        relayAllowsInsecureTLS: Bool = false,
        appGroupIdentifier: String?
    ) {
        self.backendMode = backendMode
        self.geminiAPIKey = geminiAPIKey
        self.geminiModel = geminiModel
        self.geminiTranscriptionModel = geminiTranscriptionModel
        self.relayBaseURL = relayBaseURL
        self.relayBearerToken = relayBearerToken
        self.relayStreamPath = relayStreamPath
        self.relayAllowsInsecureTLS = relayAllowsInsecureTLS
        self.appGroupIdentifier = appGroupIdentifier
    }

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        let environment = processInfo.environment

        let backendMode = AIBackendMode(
            rawValue: value(for: "AI_BACKEND_MODE", bundle: bundle, environment: environment)?.lowercased() ?? ""
        ) ?? .direct

        let geminiAPIKey = value(for: "GEMINI_API_KEY", bundle: bundle, environment: environment)
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

        return AppConfiguration(
            backendMode: backendMode,
            geminiAPIKey: geminiAPIKey,
            geminiModel: geminiModel,
            geminiTranscriptionModel: geminiTranscriptionModel,
            relayBaseURL: relayBaseURL,
            relayBearerToken: relayBearerToken,
            relayStreamPath: relayStreamPath,
            relayAllowsInsecureTLS: relayAllowsInsecureTLS,
            appGroupIdentifier: appGroupIdentifier
        )
    }

    var isAIConfigured: Bool {
        switch backendMode {
        case .direct:
            return geminiAPIKey != nil
        case .relay:
            return relayConfigurationIssue == nil
        }
    }

    var backendSummary: String {
        switch backendMode {
        case .direct:
            return backendMode.displayName
        case .relay:
            return L10n.format(
                "backend.relay.summary",
                relayBaseURL?.host() ?? L10n.tr("backend.url_invalid")
            )
        }
    }

    var storageSummary: String {
        if let appGroupIdentifier {
            return L10n.format("storage.app_group.requested", appGroupIdentifier)
        }

        #if os(watchOS)
        return L10n.tr("storage.local.watch")
        #else
        return L10n.tr("storage.local.iphone")
        #endif
    }

    var configurationMessage: String {
        switch backendMode {
        case .direct:
            guard geminiAPIKey == nil else {
                return L10n.tr("configuration.gemini.ready")
            }
            return L10n.tr("configuration.gemini.missing_api_key")
        case .relay:
            if let relayConfigurationIssue {
                return relayConfigurationIssue
            }
            return L10n.tr("configuration.relay.ready")
        }
    }

    var voiceInputConfigurationMessage: String? {
        switch backendMode {
        case .direct:
            guard geminiAPIKey == nil else {
                return nil
            }

            return L10n.tr("configuration.voice.needs_api_key")
        case .relay:
            if let relayConfigurationIssue {
                return relayConfigurationIssue
            }

            return nil
        }
    }

    var relayStreamURL: URL? {
        guard hasValidRelayBaseURL, let relayBaseURL else {
            return nil
        }

        return relayBaseURL.appending(path: relayStreamPath)
    }

    var relayTranscriptionURL: URL? {
        guard hasValidRelayBaseURL, let relayBaseURL else {
            return nil
        }

        return relayBaseURL.appending(path: "v1/audio/transcribe")
    }

    var relayMemoryExtractURL: URL? {
        guard hasValidRelayBaseURL, let relayBaseURL else {
            return nil
        }

        return relayBaseURL.appending(path: "v1/memory/extract")
    }

    private var hasValidRelayBaseURL: Bool {
        guard let relayBaseURL else {
            return false
        }

        return relayBaseURL.scheme?.isEmpty == false && relayBaseURL.host()?.isEmpty == false
    }

    private var relayConfigurationIssue: String? {
        guard relayBaseURL != nil else {
            return L10n.tr("configuration.relay.missing_base_url")
        }

        guard hasValidRelayBaseURL else {
            return L10n.tr("configuration.relay.invalid_base_url")
        }

        guard relayBearerToken != nil else {
            return L10n.tr("configuration.relay.missing_bearer")
        }

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

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
