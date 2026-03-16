//
//  AIChatApp.swift
//  AIChat Watch App
//
//  Created by zhb on 2026/3/7.
//

import SwiftUI

#if os(watchOS)
@main
struct AIChat_Watch_AppApp: App {
    @StateObject private var chatStore: ChatStore
    private let initialConversationID: UUID?
    private let uiTestLaunchDestination: UITestLaunchDestination?

    init() {
        #if DEBUG
        if let bootstrap = UITestBootstrap.makeIfNeeded() {
            _chatStore = StateObject(wrappedValue: bootstrap.store)
            initialConversationID = bootstrap.initialConversationID
            uiTestLaunchDestination = bootstrap.launchDestination
            return
        }
        #endif

        let configuration = AppConfiguration.load()
        let repository = ConversationRepository(configuration: configuration)
        let service = AIServiceFactory.makeService(configuration: configuration)
        let transcriptionService = AIServiceFactory.makeTranscriptionService(configuration: configuration)
        let memoryMaintenanceService = AIServiceFactory.makeMemoryMaintenanceService(configuration: configuration)
        let syncBridge = CompanionSyncBridge()
        _chatStore = StateObject(
            wrappedValue: ChatStore(
                repository: repository,
                aiService: service,
                transcriptionService: transcriptionService,
                memoryMaintenanceService: memoryMaintenanceService,
                configuration: configuration,
                syncBridge: syncBridge
            )
        )
        initialConversationID = nil
        uiTestLaunchDestination = nil
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if case let .conversationDetail(conversationID)? = uiTestLaunchDestination {
                    NavigationStack {
                        ConversationDetailView(conversationID: conversationID)
                    }
                } else if uiTestLaunchDestination == .formulaHarness {
                    FormulaZoomHarnessView()
                } else {
                    ContentView(initialConversationID: initialConversationID)
                }
            }
            .environmentObject(chatStore)
            .background(WatchDisplayStateObserver())
        }
    }
}

private struct WatchDisplayStateObserver: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Color.clear
            .onAppear {
                WatchDisplayStateMonitor.shared.updateLuminanceReduced(isLuminanceReduced)
            }
            .onChange(of: isLuminanceReduced) { _, newValue in
                WatchDisplayStateMonitor.shared.updateLuminanceReduced(newValue)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum UITestLaunchDestination: Equatable {
    case root
    case conversationDetail(UUID)
    case formulaHarness
}

#if DEBUG
private struct UITestBootstrap {
    let store: ChatStore
    let initialConversationID: UUID?
    let launchDestination: UITestLaunchDestination

    static func makeIfNeeded() -> UITestBootstrap? {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["AIChat_UI_TEST_SCENARIO"] else {
            return nil
        }

        switch scenario {
        case "formula_zoom":
            return UITestBootstrap(
                store: ChatStore.previewStore(conversations: []),
                initialConversationID: nil,
                launchDestination: .formulaHarness
            )
        case "tool_entry":
            let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID()
            let conversation = ConversationThread(
                id: conversationID,
                title: "Tool Entry Test",
                messages: [
                    ChatMessage(
                        role: .assistant,
                        text: "Use the tool entry to enable search or code execution."
                    )
                ]
            )

            return UITestBootstrap(
                store: ChatStore.previewStore(conversations: [conversation]),
                initialConversationID: nil,
                launchDestination: .conversationDetail(conversationID)
            )
        case "conversation_navigation":
            let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000201") ?? UUID()
            let conversation = ConversationThread(
                id: conversationID,
                title: "Navigation Test",
                messages: [
                    ChatMessage(
                        role: .assistant,
                        text: "打开这个对话，确认 watch 端详情页能正常进入。"
                    )
                ]
            )

            return UITestBootstrap(
                store: ChatStore.previewStore(conversations: [conversation]),
                initialConversationID: nil,
                launchDestination: .root
            )
        case "conversation_delete_persistence":
            return makeDeletePersistenceBootstrap(environment: environment)
        case "conversation_autoscroll_interrupt":
            return makeAutoScrollInterruptBootstrap()
        default:
            return nil
        }
    }

    private static func makeAutoScrollInterruptBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000401") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_400_500)
        var messages: [ChatMessage] = []

        for index in 1...10 {
            let baseDate = seededDate.addingTimeInterval(Double(index * 60))
            messages.append(
                ChatMessage(
                    role: .user,
                    text: "Question \(index): summarize item \(index) and keep the reply structured.",
                    createdAt: baseDate
                )
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Answer \(index): a seeded paragraph that makes the transcript tall enough for scrolling during the UI test.",
                    createdAt: baseDate.addingTimeInterval(20)
                )
            )
        }

        messages.append(
            ChatMessage(
                role: .user,
                text: "Give me a long final answer that arrives in multiple chunks so I can interrupt auto scroll.",
                createdAt: seededDate.addingTimeInterval(800)
            )
        )

        let conversation = ConversationThread(
            id: conversationID,
            title: "Auto Scroll Interrupt",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(800),
            isFavorite: false,
            messages: messages
        )

        let store = ChatStore.previewStore(
            conversations: [conversation],
            aiService: UITestAutoScrollStreamingService(),
            completionFeedbackProvider: NoopCompletionFeedbackProvider()
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await store.retryLatestReply(in: conversationID)
        }

        return UITestBootstrap(
            store: store,
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeDeletePersistenceBootstrap(
        environment: [String: String]
    ) -> UITestBootstrap? {
        let storageRootURL = URL(
            fileURLWithPath: environment["AIChat_UI_TEST_STORAGE_ROOT"] ??
                FileManager.default.temporaryDirectory
                .appendingPathComponent("AIChatUITestDeletePersistence", isDirectory: true)
                .path,
            isDirectory: true
        )
        let defaultsSuiteName = environment["AIChat_UI_TEST_DEFAULTS_SUITE"] ??
            "AIChatUITests.DeletePersistence"
        let shouldResetStorage = environment["AIChat_UI_TEST_DELETE_RESET"] == "1"
        let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard

        if shouldResetStorage {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
            try? FileManager.default.removeItem(at: storageRootURL)
        }

        let configuration = AppConfiguration(
            backendMode: .direct,
            geminiAPIKey: "ui-test-key",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: nil,
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: storageRootURL
        )
        let rawDeviceIdentifier = "UI-TEST-WATCH-DELETE-PERSISTENCE"
        let deviceToken = OfflineActivation.deviceToken(for: rawDeviceIdentifier)
        let deviceIdentity = WatchDeviceIdentity(
            rawIdentifier: rawDeviceIdentifier,
            deviceToken: deviceToken,
            displayToken: OfflineActivation.displayToken(for: deviceToken)
        )

        seedUITestActivationStateIfNeeded(
            defaults: defaults,
            deviceToken: deviceToken
        )

        if shouldResetStorage {
            seedDeletePersistenceConversationIfNeeded(
                at: storageRootURL,
                conversationID: UUID(uuidString: "00000000-0000-0000-0000-000000000301") ?? UUID()
            )
        }

        let store = ChatStore(
            repository: repository,
            aiService: AIServiceFactory.makeService(configuration: configuration),
            transcriptionService: AIServiceFactory.makeTranscriptionService(configuration: configuration),
            configuration: configuration,
            syncBridge: CompanionSyncBridge(),
            activationRepository: ActivationRepository(defaults: defaults),
            deviceIdentity: deviceIdentity,
            defaults: defaults
        )

        return UITestBootstrap(
            store: store,
            initialConversationID: nil,
            launchDestination: .root
        )
    }

    private static func seedUITestActivationStateIfNeeded(
        defaults: UserDefaults,
        deviceToken: UInt64
    ) {
        let storageKey = "offline_activation_state_v1"
        guard defaults.data(forKey: storageKey) == nil else {
            return
        }

        let activeState = OfflineActivationState(
            license: OfflineActivationLicense(
                deviceToken: deviceToken,
                requestIssuedAt: .now,
                validFrom: .now,
                validUntil: nil,
                messageLimit: nil,
                modelMask: LicensedModelCatalog.unrestrictedMask
            ),
            activationCodeFingerprint: "ui-test",
            activatedAt: .now,
            usedMessageCount: 0
        )

        if let data = try? JSONEncoder().encode(activeState) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private static func seedDeletePersistenceConversationIfNeeded(
        at storageRootURL: URL,
        conversationID: UUID
    ) {
        try? FileManager.default.createDirectory(at: storageRootURL, withIntermediateDirectories: true)

        let conversationFileURL = storageRootURL.appendingPathComponent(
            "\(conversationID.uuidString).json",
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: conversationFileURL.path) == false else {
            return
        }

        let seededDate = Date(timeIntervalSince1970: 1_762_400_400)
        let conversation = ConversationThread(
            id: conversationID,
            title: "Delete Persistence",
            createdAt: seededDate,
            updatedAt: seededDate,
            isFavorite: false,
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: "Delete this conversation, relaunch the app, and confirm it stays gone.",
                    createdAt: seededDate
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(conversation) {
            try? data.write(to: conversationFileURL, options: [.atomic])
        }
    }
}

private struct UITestAutoScrollStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.thoughtDelta("Preparing a deterministic streaming reply for auto-scroll UI verification."))

                let chunks = [
                    "Chunk 1: This reply is intentionally long so the detail view keeps receiving streaming updates while the UI test scrolls away from the bottom.\n\n",
                    "Chunk 2: After the interrupt happens, the same assistant bubble should never trigger another programmatic scroll-to-bottom call.\n\n",
                    "Chunk 3: The UI test waits while these extra chunks arrive and checks a debug counter exposed from the conversation view.\n\n",
                    "Chunk 4: The streaming window is intentionally stretched so the UI test can reliably observe an active reply before interrupting it.\n\n",
                    "Chunk 5: Once the user has scrolled away, later deltas in this same bubble should keep rendering without forcing the scroll view to jump.\n\n",
                    "Chunk 6: If auto scroll restarts inside the same answer bubble, the counter would increase and the test would fail."
                ]

                for chunk in chunks {
                    guard Task.isCancelled == false else {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continuation.yield(.answerDelta(chunk))
                }

                continuation.finish()
            }
        }
    }
}
#endif
#endif
