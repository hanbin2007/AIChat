//
//  AppEnvironment.swift
//  AIChat Watch App
//
//  Composition root for the rewritten Watch backend. Owns the
//  `RelayAPIClient` actor and the domain services that each ViewModel
//  depends on. Constructed once at app launch from `AppConfiguration`
//  and the device identity, then injected into the SwiftUI view tree
//  via `.environment(\.appEnvironment, ...)`.
//
//  Strict MVVM: `AppEnvironment` does NOT hold ViewModels. Views
//  construct their own VMs from the injected services. This keeps
//  cross-screen state out of the composition root.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let deviceIdentity: WatchDeviceIdentity
    let modelContainer: ModelContainer?
    let relayAPI: RelayAPIClient?
    let conversations: ConversationPersistence?
    let billingPersistence: BillingPersistence?
    let billingService: RelayBillingService?
    let activationService: RelayActivationService?
    let chatService: (any ChatServiceProtocol)?
    let transcriptionService: TranscriptionService?
    let memoryService: MemoryService?
    let connectionMonitor: RelayConnectionMonitor
    let settingsService: SettingsService
    let streamingTextPacer: StreamingTextPacer
    let backgroundSession: BackgroundSessionCoordinator
    let completionFeedback: CompletionFeedbackProvider

    init(
        configuration: AppConfiguration,
        deviceIdentity: WatchDeviceIdentity
    ) {
        self.configuration = configuration
        self.deviceIdentity = deviceIdentity
        self.connectionMonitor = RelayConnectionMonitor()
        let settingsService = SettingsService(
            defaults: .standard,
            fallbackModel: configuration.geminiModel,
            fallbackTranscriptionModel: configuration.geminiTranscriptionModel
        )
        self.settingsService = settingsService
        self.streamingTextPacer = StreamingTextPacer()
        self.backgroundSession = BackgroundSessionCoordinator()
        self.completionFeedback = CompletionFeedbackProvider.makeDefault()

        // 1. Build the V2 SwiftData container. V2 is treated as the
        // initial install schema — no V1 migration path exists.
        let container = Self.buildContainer(configuration: configuration)
        self.modelContainer = container

        // 2. Persistence actors.
        if let container {
            self.conversations = ConversationPersistence(container: container)
            self.billingPersistence = BillingPersistence(container: container)
        } else {
            self.conversations = nil
            self.billingPersistence = nil
        }

        // 3. Networking + relay-aware services.
        if let context = Self.makeRequestContext(
            configuration: configuration,
            deviceID: deviceIdentity.rawIdentifier
        ) {
            let client = RelayAPIClient(context: context)
            self.relayAPI = client
            self.billingService = RelayBillingService(
                networking: client,
                deviceIdentity: deviceIdentity
            )
            self.activationService = RelayActivationService(
                networking: client,
                deviceIdentity: deviceIdentity
            )
            self.transcriptionService = TranscriptionService(api: client)
            if let conversations = self.conversations {
                let core = ChatService(
                    api: client,
                    persistence: conversations,
                    defaultModel: configuration.geminiModel
                )
                // Wrap the core service so connect-time failures retry
                // transparently; the policy reads the latest user
                // setting on every send.
                self.chatService = RetryingChatService(
                    inner: core,
                    policyProvider: { @Sendable [settingsService] in
                        await MainActor.run {
                            RetryingChatService.RetryPolicy(
                                maxAttempts: settingsService.sendFailureRetryLimit,
                                initialDelayNanos: 2_000_000_000,
                                factor: 2.0
                            )
                        }
                    }
                )
            } else {
                self.chatService = nil
            }
            // Memory service uses the heuristic + model-backed pipeline
            // wrapping the new relay extractor.
            let extractor = RelayMemoryExtractor(api: client)
            let modelBacked = ModelBackedMemoryMaintenanceService(
                extractor: extractor,
                defaultModel: configuration.geminiModel
            )
            self.memoryService = MemoryService(maintenance: modelBacked)
        } else {
            self.relayAPI = nil
            self.billingService = nil
            self.activationService = nil
            self.chatService = nil
            self.transcriptionService = nil
            // Even without a relay, the heuristic memory pipeline runs
            // locally and is useful for archive segmentation.
            self.memoryService = MemoryService(maintenance: HeuristicMemoryMaintenanceService())
        }
    }

    /// Construct a `RelayRequestContext` from `AppConfiguration` if the
    /// relay base URL is configured. Bearer token may be `nil` at
    /// bootstrap time — the activation flow obtains it on first call.
    static func makeRequestContext(
        configuration: AppConfiguration,
        deviceID: String
    ) -> RelayRequestContext? {
        guard let baseURL = configuration.relayBaseURL else {
            return nil
        }
        return RelayRequestContext(
            baseURL: baseURL,
            deviceID: deviceID,
            bearerToken: configuration.resolvedRelayBearerToken,
            allowsInsecureTLS: configuration.relayAllowsInsecureTLS
        )
    }

    private static func buildContainer(configuration: AppConfiguration) -> ModelContainer? {
        try? AIChatModelContainer.makeOnDisk(
            appGroupIdentifier: configuration.appGroupIdentifier
        )
    }
}

// MARK: - SwiftUI environment plumbing

private struct AppEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppEnvironment? = nil
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
