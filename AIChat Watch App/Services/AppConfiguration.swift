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
            return "Direct Gemini"
        case .relay:
            return "Relay Gateway"
        }
    }
}

struct AppConfiguration: Equatable {
    let backendMode: AIBackendMode
    let geminiAPIKey: String?
    let geminiModel: String
    let relayBaseURL: URL?
    let relayBearerToken: String?
    let relayStreamPath: String
    let appGroupIdentifier: String?

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        let environment = processInfo.environment

        let backendMode = AIBackendMode(
            rawValue: value(for: "AI_BACKEND_MODE", bundle: bundle, environment: environment)?.lowercased() ?? ""
        ) ?? .direct

        let geminiAPIKey = value(for: "GEMINI_API_KEY", bundle: bundle, environment: environment)
        let geminiModel = value(for: "GEMINI_MODEL", bundle: bundle, environment: environment) ?? "gemini-3-flash-preview"
        let relayBaseURL = value(for: "AI_RELAY_BASE_URL", bundle: bundle, environment: environment)
            .flatMap(URL.init(string:))
        let relayBearerToken = value(for: "AI_RELAY_BEARER_TOKEN", bundle: bundle, environment: environment)
        let relayStreamPath = value(for: "AI_RELAY_STREAM_PATH", bundle: bundle, environment: environment) ?? "v1/chat/stream"
        let appGroupIdentifier = value(for: "APP_GROUP_IDENTIFIER", bundle: bundle, environment: environment)

        return AppConfiguration(
            backendMode: backendMode,
            geminiAPIKey: geminiAPIKey,
            geminiModel: geminiModel,
            relayBaseURL: relayBaseURL,
            relayBearerToken: relayBearerToken,
            relayStreamPath: relayStreamPath,
            appGroupIdentifier: appGroupIdentifier
        )
    }

    var isAIConfigured: Bool {
        switch backendMode {
        case .direct:
            return geminiAPIKey != nil
        case .relay:
            return relayBaseURL != nil && relayBearerToken != nil
        }
    }

    var backendSummary: String {
        switch backendMode {
        case .direct:
            return "\(backendMode.displayName) • \(AIModelCatalog.shortLabel(for: geminiModel))"
        case .relay:
            return "\(backendMode.displayName) • \(relayBaseURL?.host() ?? "URL missing")"
        }
    }

    var storageSummary: String {
        if let appGroupIdentifier {
            return "App Group requested: \(appGroupIdentifier)"
        }

        return "Local watch storage"
    }

    var configurationMessage: String {
        switch backendMode {
        case .direct:
            guard geminiAPIKey == nil else {
                return "Gemini is ready."
            }
            return "Add GEMINI_API_KEY in Config/Secrets.xcconfig or the scheme environment before sending messages."
        case .relay:
            if relayBaseURL == nil || relayBearerToken == nil {
                return "Relay mode needs AI_RELAY_BASE_URL and AI_RELAY_BEARER_TOKEN in Config/Secrets.xcconfig."
            }
            return "Relay gateway is ready."
        }
    }

    var relayStreamURL: URL? {
        guard let relayBaseURL else {
            return nil
        }

        return relayBaseURL.appending(path: relayStreamPath)
    }

    private static func value(
        for key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        environment[key]?.nonEmptyTrimmed ??
        (bundle.object(forInfoDictionaryKey: key) as? String)?.nonEmptyTrimmed
    }
}
