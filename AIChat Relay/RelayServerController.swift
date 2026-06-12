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
    @Published private(set) var debugEntries: [RelayDebugEntry] = []
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var completedRequestCount: Int = 0
    @Published private(set) var failedRequestCount: Int = 0
    @Published private(set) var lastRequestAt: Date?
    @Published private(set) var lastFailureAt: Date?
    @Published private(set) var lastFailureMessage: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var feedback: RelayActionFeedback?
    @Published private(set) var billingAccounts: [RelayAccountSummary] = []
    @Published private(set) var billingDevices: [RelayDeviceSummary] = []
    @Published private(set) var billingKeys: [RelayKeySummary] = []
    @Published private(set) var billingGrants: [RelayGrantSummary] = []
    @Published private(set) var billingUsage: [RelayUsageSummary] = []
    @Published private(set) var billingPlans: [RelayPlanCatalogItem] = []
    @Published private(set) var billingPolicy: RelayMeteringPolicySnapshot = RelayBillingStore.defaultPolicy

    let settings: RelaySettingsStore

    private var hasHandledInitialLaunch = false
    private var cancellables: Set<AnyCancellable> = []
    private var feedbackDismissTask: Task<Void, Never>?
    private let eventSink: RelayServerEventSink
    private let server: LocalRelayServer
    private let billingStore: RelayBillingStore

    init(settings: RelaySettingsStore? = nil) {
        let resolvedSettings = settings ?? RelaySettingsStore()
        let eventSink = RelayServerEventSink()
        let billingStore = RelayBillingStore()

        self.settings = resolvedSettings
        self.eventSink = eventSink
        self.billingStore = billingStore
        self.server = LocalRelayServer(
            configurationProvider: Self.makeConfigurationProvider(settings: resolvedSettings),
            eventHandler: Self.makeEventHandler(sink: eventSink),
            billingStore: billingStore
        )

        self.eventSink.controller = self

        self.settings.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        Task {
            await refreshBillingSnapshot()
        }
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

    var activeBindingMode: String {
        settings.allowNetworkClients ? "LAN + Localhost" : "Localhost only"
    }

    var requestSuccessRate: Double? {
        let total = completedRequestCount + failedRequestCount
        guard total > 0 else {
            return nil
        }

        return Double(completedRequestCount) / Double(total)
    }

    var setupSteps: [RelaySetupStep] {
        [
            RelaySetupStep(
                title: "Gemini access",
                detail: settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Add a Gemini API key to enable upstream requests."
                    : "API key is stored securely in the macOS Keychain.",
                status: settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .blocked : .complete
            ),
            RelaySetupStep(
                title: "Relay authentication",
                detail: settings.relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Generate or paste a bearer token for client authentication."
                    : "Bearer token is ready and copied into generated client snippets.",
                status: settings.relayBearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .blocked : .complete
            ),
            RelaySetupStep(
                title: "Listener configuration",
                detail: settings.validatedPort == nil
                    ? "Choose a valid TCP port before the relay can bind."
                    : "Relay will bind to port \(settings.runtimeConfiguration.port) in \(activeBindingMode.lowercased()).",
                status: settings.validatedPort == nil ? .blocked : .complete
            ),
            RelaySetupStep(
                title: "Traffic acceptance",
                detail: isRunning
                    ? "Relay is online and ready to receive AIChat requests."
                    : configurationIssue == nil
                        ? "Start the relay to expose `/health` and API endpoints."
                        : "Resolve the configuration issues above, then start the relay.",
                status: isRunning ? .complete : (configurationIssue == nil ? .pending : .blocked)
            )
        ]
    }

    var completedSetupStepCount: Int {
        setupSteps.filter { $0.status == .complete }.count
    }

    var billingAccountCount: Int {
        billingAccounts.count
    }

    var activeKeyCount: Int {
        billingKeys.filter { $0.state == .active }.count
    }

    var totalManagedCredits: Int {
        billingAccounts.reduce(into: 0) { partialResult, account in
            partialResult += account.creditBalance
        }
    }

    var clientConfigurationSnippet: String {
        """
        AI_RELAY_BASE_URL = \(Self.xcconfigEscaped(recommendedClientBaseURL))
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
            showFeedback(
                title: "Configuration Required",
                message: configurationIssue,
                style: .warning
            )
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
            showFeedback(
                title: "Relay Failed",
                message: message,
                style: .error
            )
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
        showFeedback(
            title: "Relay Token Updated",
            message: "A new bearer token was generated and stored in the Keychain.",
            style: .success
        )
    }

    func copyToPasteboard(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        appendLog(level: .info, message: "Copied \(label) to the pasteboard.")
        showFeedback(
            title: "Copied",
            message: "Copied \(label) to the pasteboard.",
            style: .success
        )
    }

    func clearDebugEntries() {
        debugEntries.removeAll()
        appendLog(level: .info, message: "Cleared relay debug entries.")
        showFeedback(
            title: "Debug Cleared",
            message: "Removed captured debug payloads from the dashboard.",
            style: .info
        )
    }

    func clearLogEntries() {
        logEntries.removeAll()
        showFeedback(
            title: "Activity Cleared",
            message: "Removed activity log entries from the dashboard.",
            style: .info
        )
    }

    func openHealthURL() {
        guard let url = URL(string: relayHealthURL) else {
            showFeedback(
                title: "Invalid URL",
                message: "The health endpoint could not be opened because the relay URL is invalid.",
                style: .error
            )
            return
        }

        NSWorkspace.shared.open(url)
        appendLog(level: .info, message: "Opened the relay health endpoint in the default browser.")
        showFeedback(
            title: "Health Check Opened",
            message: "Opened \(relayHealthURL) in the default browser.",
            style: .info
        )
    }

    func dismissFeedback() {
        feedbackDismissTask?.cancel()
        feedbackDismissTask = nil
        feedback = nil
    }

    func refreshBillingSnapshot() async {
        let snapshot = await billingStore.snapshot()
        billingAccounts = snapshot.accounts
        billingDevices = snapshot.devices
        billingKeys = snapshot.keys
        billingGrants = snapshot.grants
        billingUsage = snapshot.usage
        billingPlans = snapshot.plans
        billingPolicy = snapshot.meteringPolicy
    }

    func updateAccount(
        accountID: UUID,
        displayName: String?,
        adminNote: String?,
        state: RelayAccountState?,
        planID: String?
    ) {
        Task {
            do {
                try await billingStore.modifyAccount(
                    accountID: accountID,
                    displayName: displayName,
                    adminNote: adminNote,
                    state: state,
                    planID: planID
                )
                await refreshBillingSnapshot()
            } catch {
                showFeedback(title: "Account Update Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    func updateDevice(
        deviceID: String,
        alias: String?,
        note: String?
    ) {
        Task {
            do {
                try await billingStore.modifyDevice(deviceID: deviceID, alias: alias, note: note)
                await refreshBillingSnapshot()
            } catch {
                showFeedback(title: "Device Update Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    func updateKey(
        keyID: UUID,
        state: RelayKeyState?,
        note: String?
    ) {
        Task {
            do {
                try await billingStore.modifyKey(keyID: keyID, state: state, note: note)
                await refreshBillingSnapshot()
            } catch {
                showFeedback(title: "Key Update Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    func updateGrant(
        grantID: UUID,
        remainingCredits: Int?,
        note: String?
    ) {
        Task {
            do {
                try await billingStore.modifyGrant(
                    grantID: grantID,
                    remainingCredits: remainingCredits,
                    note: note
                )
                await refreshBillingSnapshot()
            } catch {
                showFeedback(title: "Grant Update Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    func grantCredits(
        accountID: UUID,
        credits: Int,
        source: RelayAccessSource = .subscription,
        expiresAt: Date?,
        note: String?
    ) {
        Task {
            do {
                try await billingStore.grantCredits(
                    accountID: accountID,
                    credits: credits,
                    source: source,
                    expiresAt: expiresAt,
                    note: note
                )
                await refreshBillingSnapshot()
            } catch {
                showFeedback(title: "Credit Grant Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    func saveBillingPolicy(_ policy: RelayMeteringPolicySnapshot, plans: [RelayPlanCatalogItem]) {
        Task {
            do {
                try await billingStore.updateMeteringPolicy(policy, plans: plans)
                await refreshBillingSnapshot()
                showFeedback(title: "Policy Saved", message: "Updated billing plans and metering policy.", style: .success)
            } catch {
                showFeedback(title: "Policy Save Failed", message: error.localizedDescription, style: .error)
            }
        }
    }

    private func handleServerEvent(_ event: RelayServerEvent) {
        switch event {
        case .didStart(let port):
            status = .running
            startedAt = .now
            showFeedback(
                title: "Relay Online",
                message: "Listening on port \(port) and ready to accept requests.",
                style: .success
            )
        case .didStop:
            status = .stopped
            startedAt = nil
            appendLog(
                level: .info,
                category: .lifecycle,
                message: "Relay server stopped."
            )
            showFeedback(
                title: "Relay Stopped",
                message: "The local relay listener has been stopped.",
                style: .info
            )
        case let .didReceiveRequest(path, method, remoteAddress, context):
            requestCount += 1
            lastRequestAt = .now
            appendLog(
                level: .info,
                category: .request,
                message: requestLogMessage(prefix: "Received", path: path, remoteAddress: remoteAddress),
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                context: context
            )
            Task {
                await refreshBillingSnapshot()
            }
        case let .didCompleteRequest(path, method, remoteAddress, context):
            completedRequestCount += 1
            appendLog(
                level: .success,
                category: .completed,
                message: requestLogMessage(prefix: "Completed", path: path, remoteAddress: remoteAddress),
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                statusCode: 200,
                context: context
            )
            Task {
                await refreshBillingSnapshot()
            }
        case let .didFailRequest(path, method, remoteAddress, statusCode, message, context):
            let level: RelayLogLevel = statusCode >= 500 ? .error : .warning
            failedRequestCount += 1
            lastFailureAt = .now
            lastFailureMessage = message
            appendLog(
                level: level,
                category: .failure,
                message: requestLogMessage(
                    prefix: "Failed [\(statusCode)]",
                    path: path,
                    remoteAddress: remoteAddress,
                    suffix: message
                ),
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                context: context
            )
            Task {
                await refreshBillingSnapshot()
            }
        case .debug(let event):
            appendDebug(event)
        case let .log(level, message, category, method, path, remoteAddress, statusCode, context):
            appendLog(
                level: level,
                category: category,
                message: message,
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                context: context
            )
        case .listenerFailed(let message):
            status = .failed(message)
            startedAt = nil
            appendLog(
                level: .error,
                category: .lifecycle,
                message: "Listener failed: \(message)"
            )
            showFeedback(
                title: "Relay Failed",
                message: message,
                style: .error
            )
        }
    }

    private func appendLog(
        level: RelayLogLevel,
        category: RelayLogCategory = .system,
        message: String,
        method: String? = nil,
        path: String? = nil,
        remoteAddress: String? = nil,
        statusCode: Int? = nil,
        context: RelayActorContext? = nil
    ) {
        logEntries.append(
            RelayLogEntry(
                timestamp: .now,
                level: level,
                category: category,
                message: message,
                method: method,
                path: path,
                remoteAddress: remoteAddress,
                statusCode: statusCode,
                context: context
            )
        )

        if logEntries.count > 500 {
            logEntries.removeFirst(logEntries.count - 500)
        }
    }

    private func appendDebug(_ event: RelayDebugEvent) {
        debugEntries.append(
            RelayDebugEntry(
                timestamp: .now,
                source: event.source,
                kind: event.kind,
                title: event.title,
                summary: event.summary,
                method: event.method,
                path: event.path,
                address: event.address,
                statusCode: event.statusCode,
                body: event.body,
                context: event.context
            )
        )

        if debugEntries.count > 300 {
            debugEntries.removeFirst(debugEntries.count - 300)
        }
    }

    private func requestLogMessage(
        prefix: String,
        path: String,
        remoteAddress: String?,
        suffix: String? = nil
    ) -> String {
        var message = "\(prefix) \(path)"

        if let remoteAddress {
            message.append(" from \(remoteAddress)")
        }

        if let suffix, suffix.isEmpty == false {
            message.append(" • \(suffix)")
        }

        message.append(".")
        return message
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

    private static func xcconfigEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "//", with: "/$()/")
    }

    func showFeedback(
        title: String,
        message: String,
        style: RelayFeedbackStyle
    ) {
        feedbackDismissTask?.cancel()

        let newFeedback = RelayActionFeedback(
            title: title,
            message: message,
            style: style
        )
        feedback = newFeedback

        feedbackDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)

            await MainActor.run {
                guard let self, self.feedback?.id == newFeedback.id else {
                    return
                }

                self.feedback = nil
                self.feedbackDismissTask = nil
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
