//
//  RelayServerController.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/8.
//

import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class RelayServerController: ObservableObject {
    @Published private(set) var status: RelayServerStatus = .stopped
    @Published private(set) var logEntries: [RelayLogEntry] = []
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var lastRequestAt: Date?

    let settings: RelaySettingsStore

    private var hasHandledInitialLaunch = false
    private var cancellables: Set<AnyCancellable> = []
    private let eventSink: RelayServerEventSink
    private let server: LocalRelayServer

    init(settings: RelaySettingsStore? = nil) {
        let resolvedSettings = settings ?? RelaySettingsStore()
        let eventSink = RelayServerEventSink()

        self.settings = resolvedSettings
        self.eventSink = eventSink
        self.server = LocalRelayServer(
            configurationProvider: Self.makeConfigurationProvider(settings: resolvedSettings),
            eventHandler: Self.makeEventHandler(sink: eventSink)
        )

        self.eventSink.controller = self

        self.settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var configurationIssue: String? {
        settings.configurationIssue
    }

    var isRunning: Bool {
        if case .running = status {
            return true
        }
        return false
    }

    var isStarting: Bool {
        if case .starting = status {
            return true
        }
        return false
    }

    var statusText: String {
        switch status {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .failed:
            return "Failed"
        }
    }

    var statusMessage: String {
        switch status {
        case .stopped:
            return "The relay app is ready, but the local HTTP server is not running."
        case .starting:
            return "Binding the local HTTP listener and preparing the Gemini stream bridge."
        case .running:
            if settings.allowNetworkClients {
                return "The relay is accepting requests from this Mac and devices on the same LAN."
            }
            return "The relay is accepting requests from this Mac only."
        case .failed(let message):
            return message
        }
    }

    var endpoints: [RelayEndpoint] {
        guard let port = settings.validatedPort else {
            return []
        }

        var resolvedEndpoints = [
            RelayEndpoint(
                title: "Localhost",
                urlString: "http://127.0.0.1:\(port)",
                detail: "Use this when the client runs on the same Mac."
            )
        ]

        if settings.allowNetworkClients {
            for address in HostAddressLocator.ipv4Addresses() {
                resolvedEndpoints.append(
                    RelayEndpoint(
                        title: "LAN",
                        urlString: "http://\(address):\(port)",
                        detail: "Use this from your iPhone or Apple Watch while it is on the same network."
                    )
                )
            }
        }

        return resolvedEndpoints
    }

    var recommendedClientBaseURL: String {
        endpoints.first(where: { $0.title == "LAN" })?.urlString ?? endpoints.first?.urlString ?? "http://127.0.0.1:8787"
    }

    var relayHealthURL: String {
        "\(recommendedClientBaseURL)/health"
    }

    var clientConfigurationSnippet: String {
        """
        AI_BACKEND_MODE = relay
        AI_RELAY_BASE_URL = \(recommendedClientBaseURL)
        AI_RELAY_BEARER_TOKEN = \(settings.runtimeConfiguration.relayBearerToken)
        GEMINI_MODEL = gemini-3-flash-preview
        """
    }

    func handleInitialLaunch() {
        guard hasHandledInitialLaunch == false else {
            return
        }

        hasHandledInitialLaunch = true
        appendLog(level: .info, message: "Relay dashboard is ready.")

        if settings.autoStartOnLaunch {
            Task {
                await start()
            }
        }
    }

    func start() async {
        guard isStarting == false, isRunning == false else {
            return
        }

        if let configurationIssue = configurationIssue {
            status = .failed(configurationIssue)
            appendLog(level: .error, message: configurationIssue)
            return
        }

        status = .starting
        appendLog(level: .info, message: "Starting relay server.")

        do {
            try await server.start()
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            appendLog(level: .error, message: "Relay failed to start: \(message)")
        }
    }

    func stop() async {
        guard isRunning || isStarting else {
            return
        }

        appendLog(level: .info, message: "Stopping relay server.")
        await server.stop()
    }

    func toggleServer() {
        Task {
            if isRunning || isStarting {
                await stop()
            } else {
                await start()
            }
        }
    }

    func regenerateRelayToken() {
        settings.regenerateRelayToken()
        appendLog(level: .info, message: "Generated a new relay bearer token.")
    }

    func copyToPasteboard(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        appendLog(level: .info, message: "Copied \(label) to the pasteboard.")
    }

    private func handleServerEvent(_ event: RelayServerEvent) {
        switch event {
        case .didStart:
            status = .running
        case .didStop:
            status = .stopped
            appendLog(level: .info, message: "Relay server stopped.")
        case .didReceiveRequest(let path, let remoteAddress):
            requestCount += 1
            lastRequestAt = .now
            if let remoteAddress {
                appendLog(level: .success, message: "Handled \(path) from \(remoteAddress).")
            } else {
                appendLog(level: .success, message: "Handled \(path).")
            }
        case .log(let level, let message):
            appendLog(level: level, message: message)
        case .listenerFailed(let message):
            status = .failed(message)
            appendLog(level: .error, message: "Listener failed: \(message)")
        }
    }

    private func appendLog(level: RelayLogLevel, message: String) {
        logEntries.append(
            RelayLogEntry(
                timestamp: .now,
                level: level,
                message: message
            )
        )

        if logEntries.count > 200 {
            logEntries.removeFirst(logEntries.count - 200)
        }
    }

    private static func makeConfigurationProvider(
        settings: RelaySettingsStore
    ) -> @Sendable () async -> RelayRuntimeConfiguration {
        {
            await MainActor.run {
                settings.runtimeConfiguration
            }
        }
    }

    private static func makeEventHandler(
        sink: RelayServerEventSink
    ) -> @Sendable (RelayServerEvent) async -> Void {
        { event in
            await MainActor.run {
                sink.controller?.handleServerEvent(event)
            }
        }
    }
}

private final class RelayServerEventSink: @unchecked Sendable {
    weak var controller: RelayServerController?
}

private enum HostAddressLocator {
    static func ipv4Addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }

        defer {
            freeifaddrs(first)
        }

        var addresses: [String] = []
        var current = first

        while true {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, isRunning, isLoopback == false,
               let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )

                if result == 0 {
                    let ipAddress = String(cString: host)
                    if addresses.contains(ipAddress) == false {
                        addresses.append(ipAddress)
                    }
                }
            }

            guard let next = interface.ifa_next else {
                break
            }

            current = next
        }

        return addresses.sorted()
    }
}
