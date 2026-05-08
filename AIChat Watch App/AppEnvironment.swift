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
    let chatService: ChatService?
    let transcriptionService: TranscriptionService?
    let memoryService: MemoryService?
    let connectionMonitor: RelayConnectionMonitor
    let settingsService: SettingsService

    /// Result of the V1→V2 migration probe; nil on fresh installs that
    /// had no V1 store. Surfaced for diagnostics chrome only.
    let migrationOutcome: AIChatMigrationPlanV1ToV2.Outcome?

    init(
        configuration: AppConfiguration,
        deviceIdentity: WatchDeviceIdentity
    ) {
        self.configuration = configuration
        self.deviceIdentity = deviceIdentity
        self.connectionMonitor = RelayConnectionMonitor()
        self.settingsService = SettingsService(
            defaults: .standard,
            fallbackModel: configuration.geminiModel,
            fallbackTranscriptionModel: configuration.geminiTranscriptionModel
        )

        // 1. Build the V2 SwiftData container + run migration if V1 exists.
        let containerResult = Self.buildContainer(configuration: configuration)
        self.modelContainer = containerResult.container
        self.migrationOutcome = containerResult.outcome

        // 2. Persistence actors.
        if let container = containerResult.container {
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
                self.chatService = ChatService(
                    api: client,
                    persistence: conversations,
                    defaultModel: configuration.geminiModel
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

    private struct ContainerBuildResult {
        let container: ModelContainer?
        let outcome: AIChatMigrationPlanV1ToV2.Outcome?
    }

    private static func buildContainer(configuration: AppConfiguration) -> ContainerBuildResult {
        do {
            let container = try AIChatModelContainer.makeOnDisk(
                appGroupIdentifier: configuration.appGroupIdentifier
            )
            // Resolve the same root URL the container chose so the
            // migration plan can locate the V1 sqlite alongside it.
            let rootURL = resolvedStorageRoot(configuration: configuration)
            let outcome = AIChatMigrationPlanV1ToV2.migrateIfNeeded(
                v2Container: container,
                rootURL: rootURL
            )
            return ContainerBuildResult(container: container, outcome: outcome)
        } catch {
            return ContainerBuildResult(container: nil, outcome: nil)
        }
    }

    private static func resolvedStorageRoot(configuration: AppConfiguration) -> URL {
        let fileManager = FileManager.default
        if let appGroupIdentifier = configuration.appGroupIdentifier,
           let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url.appendingPathComponent("AIChatStore", isDirectory: true)
        }
        if let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return baseURL.appendingPathComponent("AIChatStore", isDirectory: true)
        }
        return fileManager.temporaryDirectory.appendingPathComponent("AIChatStore", isDirectory: true)
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
