//
//  RelaySettingsStore.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import Combine
import Foundation

struct RelayRuntimeConfiguration: Equatable, Sendable {
    var geminiAPIKey: String
    var relayBearerToken: String
    var port: UInt16
    var allowNetworkClients: Bool
}

@MainActor
final class RelaySettingsStore: ObservableObject {
    @Published var geminiAPIKey: String {
        didSet { defaults.set(geminiAPIKey, forKey: Keys.geminiAPIKey) }
    }

    @Published var relayBearerToken: String {
        didSet { defaults.set(relayBearerToken, forKey: Keys.relayBearerToken) }
    }

    @Published var portText: String {
        didSet { defaults.set(portText, forKey: Keys.portText) }
    }

    @Published var allowNetworkClients: Bool {
        didSet { defaults.set(allowNetworkClients, forKey: Keys.allowNetworkClients) }
    }

    @Published var autoStartOnLaunch: Bool {
        didSet { defaults.set(autoStartOnLaunch, forKey: Keys.autoStartOnLaunch) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.geminiAPIKey = defaults.string(forKey: Keys.geminiAPIKey) ?? ""

        let storedToken = defaults.string(forKey: Keys.relayBearerToken)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayBearerToken = storedToken?.isEmpty == false ? storedToken! : Self.makeRelayToken()
        self.portText = defaults.string(forKey: Keys.portText) ?? "8787"

        if defaults.object(forKey: Keys.allowNetworkClients) == nil {
            self.allowNetworkClients = true
        } else {
            self.allowNetworkClients = defaults.bool(forKey: Keys.allowNetworkClients)
        }

        if defaults.object(forKey: Keys.autoStartOnLaunch) == nil {
            self.autoStartOnLaunch = true
        } else {
            self.autoStartOnLaunch = defaults.bool(forKey: Keys.autoStartOnLaunch)
        }

        defaults.set(self.relayBearerToken, forKey: Keys.relayBearerToken)
    }

    var runtimeConfiguration: RelayRuntimeConfiguration {
        RelayRuntimeConfiguration(
            geminiAPIKey: geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            relayBearerToken: relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines),
            port: validatedPort ?? 8787,
            allowNetworkClients: allowNetworkClients
        )
    }

    var validatedPort: UInt16? {
        guard let port = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
              port > 0
        else {
            return nil
        }

        return port
    }

    var configurationIssue: String? {
        if geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a Gemini API key before starting the relay."
        }

        if relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Generate a relay bearer token before starting the relay."
        }

        if validatedPort == nil {
            return "Choose a valid TCP port."
        }

        return nil
    }

    func regenerateRelayToken() {
        relayBearerToken = Self.makeRelayToken()
    }

    private static func makeRelayToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private enum Keys {
    static let geminiAPIKey = "relay.gemini_api_key"
    static let relayBearerToken = "relay.bearer_token"
    static let portText = "relay.port_text"
    static let allowNetworkClients = "relay.allow_network_clients"
    static let autoStartOnLaunch = "relay.auto_start_on_launch"
}
