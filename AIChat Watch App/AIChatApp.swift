//
//  AIChatApp.swift
//  AIChat Watch App
//
//  Created by zhb on 2026/3/7.
//

import Combine
import Foundation
import SwiftUI

#if os(watchOS)
@main
struct AIChat_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
        let cloudSyncService = ICloudConversationSyncService(configuration: configuration)
        _chatStore = StateObject(
            wrappedValue: ChatStore(
                repository: repository,
                aiService: service,
                transcriptionService: transcriptionService,
                memoryMaintenanceService: memoryMaintenanceService,
                configuration: configuration,
                syncBridge: syncBridge,
                cloudSyncService: cloudSyncService
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
            .overlay(alignment: .topLeading) {
                #if DEBUG
                UITestHangMonitorProbe()
                #endif
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }

                Task {
                    await chatStore.refreshRemoteSyncState()
                }
            }
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
@MainActor
private final class UITestHangMonitor: ObservableObject {
    static let shared = UITestHangMonitor()

    private let isEnabled: Bool
    private let thresholdMilliseconds: Double = 500
    private let samplingIntervalNanoseconds: UInt64 = 50_000_000

    @Published private(set) var hangCount = 0
    @Published private(set) var maxObservedLatencyMilliseconds: Double = 0

    private var monitoringTask: Task<Void, Never>?

    private init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        isEnabled = environment["AIChat_UI_TEST_ENABLE_HANG_MONITOR"] == "1"
    }

    var accessibilityLabel: String {
        let maxLatency = String(format: "%.1f", maxObservedLatencyMilliseconds)
        return "enabled=\(isEnabled ? 1 : 0);count=\(hangCount);maxMs=\(maxLatency)"
    }

    func startIfNeeded() {
        guard isEnabled, monitoringTask == nil else {
            return
        }

        let samplingIntervalNanoseconds = samplingIntervalNanoseconds
        monitoringTask = Task.detached(priority: .high) {
            while Task.isCancelled == false {
                let scheduledUptime = DispatchTime.now().uptimeNanoseconds

                await MainActor.run {
                    UITestHangMonitor.shared.recordMainThreadSample(scheduledUptime: scheduledUptime)
                }

                try? await Task.sleep(nanoseconds: samplingIntervalNanoseconds)
            }
        }
    }

    private func recordMainThreadSample(scheduledUptime: UInt64) {
        let latencyNanoseconds = DispatchTime.now().uptimeNanoseconds - scheduledUptime
        let latencyMilliseconds = Double(latencyNanoseconds) / 1_000_000
        maxObservedLatencyMilliseconds = max(maxObservedLatencyMilliseconds, latencyMilliseconds)

        if latencyMilliseconds >= thresholdMilliseconds {
            hangCount += 1
        }
    }
}

private struct UITestHangMonitorProbe: View {
    @ObservedObject private var monitor = UITestHangMonitor.shared

    var body: some View {
        Text(monitor.accessibilityLabel)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .clipped()
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityIdentifier("ui-test-hang-monitor")
            .accessibilityLabel(monitor.accessibilityLabel)
            .onAppear {
                monitor.startIfNeeded()
            }
    }
}

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
        case "conversation_delete_read_only":
            let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000302") ?? UUID()
            let conversation = ConversationThread(
                id: conversationID,
                title: "Read Only Delete",
                messages: [
                    ChatMessage(
                        role: .assistant,
                        text: "这是一条从已配对设备同步来的只读会话，watch 端也应该允许删除。"
                    )
                ]
            )

            return UITestBootstrap(
                store: ChatStore.previewStore(
                    conversations: [conversation],
                    activationState: nil
                ),
                initialConversationID: nil,
                launchDestination: .root
            )
        case "conversation_autoscroll_interrupt":
            return makeAutoScrollInterruptBootstrap()
        case "conversation_touch_scroll":
            return makeTouchScrollBootstrap()
        case "conversation_list_scroll_performance":
            return makeListScrollPerformanceBootstrap()
        case "conversation_heavy_markdown":
            return makeHeavyMarkdownBootstrap()
        case "conversation_reply_completion_anchor":
            return makeReplyCompletionAnchorBootstrap()
        case "conversation_latest_message_expanded":
            return makeLatestMessageExpandedBootstrap()
        case "conversation_latest_thought_summary_collapsed":
            return makeLatestThoughtSummaryCollapsedBootstrap()
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

    private static func makeTouchScrollBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000402") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_401_000)
        var messages: [ChatMessage] = []

        let topMarker = "Touch Scroll Top Marker"
        let bottomMarker = "Touch Scroll Bottom Marker"

        for index in 1...8 {
            let baseDate = seededDate.addingTimeInterval(Double(index * 60))
            let userText = index == 1 ?
                topMarker :
                "Touch Scroll User \(index)"
            let assistantText = index == 8 ?
                bottomMarker :
                """
                Touch Scroll Assistant \(index)
                Line 2 keeps this bubble tall enough for vertical scrolling.
                Line 3 keeps the transcript stable for the UI test.
                """

            messages.append(
                ChatMessage(
                    role: .user,
                    text: userText,
                    createdAt: baseDate
                )
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: assistantText,
                    createdAt: baseDate.addingTimeInterval(20)
                )
            )
        }

        let conversation = ConversationThread(
            id: conversationID,
            title: "Touch Scroll",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(500),
            isFavorite: false,
            messages: messages
        )

        return UITestBootstrap(
            store: ChatStore.previewStore(conversations: [conversation]),
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeListScrollPerformanceBootstrap() -> UITestBootstrap {
        let seededDate = Date(timeIntervalSince1970: 1_762_401_200)
        let streamingConversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000450") ?? UUID()
        var conversations: [ConversationThread] = []

        for index in 1...48 {
            let conversationID =
                UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000005%02d", index)) ?? UUID()
            let createdAt = seededDate.addingTimeInterval(Double(48 - index) * 90)
            let title: String
            if index == 1 {
                title = "List Scroll Top Marker"
            } else if index == 48 {
                title = "List Scroll Bottom Marker"
            } else if index == 6 {
                title = "List Streaming Target"
            } else {
                title = "History Thread \(index)"
            }

            let messages: [ChatMessage]
            if index == 6 {
                messages = [
                    ChatMessage(
                        role: .assistant,
                        text: "Earlier reply that keeps the row visible while the list is being scrolled.",
                        createdAt: createdAt
                    ),
                    ChatMessage(
                        role: .user,
                        text: "Please stream one more long reply while I scroll the history list.",
                        createdAt: createdAt.addingTimeInterval(30)
                    )
                ]
            } else {
                messages = [
                    ChatMessage(
                        role: .assistant,
                        text: """
                        \(title)
                        This seeded history row includes enough text to keep list cells realistic during the performance test.
                        """,
                        createdAt: createdAt
                    )
                ]
            }

            conversations.append(
                ConversationThread(
                    id: index == 6 ? streamingConversationID : conversationID,
                    title: title,
                    createdAt: createdAt,
                    updatedAt: createdAt.addingTimeInterval(30),
                    isFavorite: index.isMultiple(of: 9),
                    messages: messages
                )
            )
        }

        let store = ChatStore.previewStore(
            conversations: conversations,
            aiService: UITestListStreamingService(),
            completionFeedbackProvider: NoopCompletionFeedbackProvider()
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await store.retryLatestReply(in: streamingConversationID)
        }

        return UITestBootstrap(
            store: store,
            initialConversationID: nil,
            launchDestination: .root
        )
    }

    private static func makeHeavyMarkdownBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000405") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_402_100)
        let repeatedBlock = Array(
            repeating: """
            ## 推导步骤
            - 先拆条件，再整理约束，再给出区间结论。
            - 关键公式：$$\\sum_{i=1}^{64} \\frac{a_i + b_i + c_i}{\\sqrt{x_i^2 + y_i^2 + z_i^2}} = \\prod_{k=1}^{16} (\\alpha_k + \\beta_k)$$
            - 代码片段：
            ```swift
            let score = values
                .enumerated()
                .map { index, value in value * Double(index + 1) }
                .reduce(0, +)
            ```
            - 结论：**$b \\in (0, \\sqrt{3}) \\cup (\\sqrt{3}, \\frac{\\sqrt{30}}{3}]$**
            """,
            count: 14
        ).joined(separator: "\n\n")

        let conversation = ConversationThread(
            id: conversationID,
            title: "Heavy Markdown",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(60),
            isFavorite: false,
            messages: [
                ChatMessage(
                    role: .assistant,
                    text: repeatedBlock,
                    createdAt: seededDate
                )
            ]
        )

        return UITestBootstrap(
            store: ChatStore.previewStore(conversations: [conversation]),
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeReplyCompletionAnchorBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000406") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_402_500)
        let conversation = ConversationThread(
            id: conversationID,
            title: "Reply Completion Anchor",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(180),
            isFavorite: false,
            messages: [
                ChatMessage(
                    role: .user,
                    text: "Give me one long structured answer and keep the start visible when you finish.",
                    createdAt: seededDate
                )
            ]
        )

        let store = ChatStore.previewStore(
            conversations: [conversation],
            aiService: UITestReplyCompletionStreamingService(),
            completionFeedbackProvider: NoopCompletionFeedbackProvider()
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await store.retryLatestReply(in: conversationID)
        }

        return UITestBootstrap(
            store: store,
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeLatestMessageExpandedBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000403") ?? UUID()
        let latestAssistantID = UUID(uuidString: "00000000-0000-0000-0000-000000004032") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_401_500)

        let conversation = ConversationThread(
            id: conversationID,
            title: "Latest Message Expanded",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(240),
            isFavorite: false,
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000004021") ?? UUID(),
                    role: .user,
                    text: "Earlier prompt that stays short.",
                    createdAt: seededDate
                ),
                ChatMessage(
                    role: .assistant,
                    text: "Earlier short reply that should not affect the latest bubble expansion rule.",
                    createdAt: seededDate.addingTimeInterval(20)
                ),
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000004022") ?? UUID(),
                    role: .user,
                    text: "Latest prompt that should keep the newest reply fully expanded.",
                    createdAt: seededDate.addingTimeInterval(120)
                ),
                ChatMessage(
                    id: latestAssistantID,
                    role: .assistant,
                    text: makeLongCollapsibleUITestReply(
                        prefix: "Latest long reply",
                        hiddenTailMarker: "Latest Hidden Tail",
                        lineCount: 15
                    ),
                    createdAt: seededDate.addingTimeInterval(140)
                )
            ]
        )

        return UITestBootstrap(
            store: ChatStore.previewStore(conversations: [conversation]),
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeLatestThoughtSummaryCollapsedBootstrap() -> UITestBootstrap {
        let conversationID = UUID(uuidString: "00000000-0000-0000-0000-000000000404") ?? UUID()
        let latestAssistantID = UUID(uuidString: "00000000-0000-0000-0000-000000004042") ?? UUID()
        let seededDate = Date(timeIntervalSince1970: 1_762_401_800)

        let conversation = ConversationThread(
            id: conversationID,
            title: "Latest Thought Summary Collapsed",
            createdAt: seededDate,
            updatedAt: seededDate.addingTimeInterval(240),
            isFavorite: false,
            messages: [
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000004041") ?? UUID(),
                    role: .user,
                    text: "Keep the newest thought summary collapsed until I open it.",
                    createdAt: seededDate
                ),
                ChatMessage(
                    id: latestAssistantID,
                    role: .assistant,
                    text: "Short latest reply body that keeps the summary card visible without adding another collapse target.",
                    thoughtSummary: makeLongUITestThoughtSummary(
                        prefix: "Latest thought summary",
                        hiddenTailMarker: "Latest Thought Summary Hidden Tail",
                        segmentCount: 18
                    ),
                    createdAt: seededDate.addingTimeInterval(20)
                )
            ]
        )

        return UITestBootstrap(
            store: ChatStore.previewStore(conversations: [conversation]),
            initialConversationID: nil,
            launchDestination: .conversationDetail(conversationID)
        )
    }

    private static func makeLongCollapsibleUITestReply(
        prefix: String,
        hiddenTailMarker: String,
        lineCount: Int
    ) -> String {
        (1...max(lineCount, 15))
            .map { index in
                if index == max(lineCount, 15) {
                    return "\(prefix) \(index): \(hiddenTailMarker)"
                }

                return "\(prefix) \(index): keep this line visible only after expansion when collapse is allowed."
            }
            .joined(separator: "\n")
    }

    private static func makeLongUITestThoughtSummary(
        prefix: String,
        hiddenTailMarker: String,
        segmentCount: Int
    ) -> String {
        (1...max(segmentCount, 12))
            .map { index in
                if index == max(segmentCount, 12) {
                    return "\(prefix) \(index): \(hiddenTailMarker)"
                }

                return "\(prefix) \(index): keep this clause available only after the summary expands."
            }
            .joined(separator: " ")
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
        let activationRepository = ActivationRepository(
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
            activationRepository: activationRepository,
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
            syncBridge: CompanionSyncBridge(isEnabled: false),
            activationRepository: activationRepository,
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
        activationRepository: ActivationRepository,
        deviceToken: UInt64
    ) {
        guard activationRepository.loadState() == nil else {
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

        try? activationRepository.saveState(activeState)
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

private struct UITestListStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.thoughtDelta("Preparing a deterministic list-row streaming update."))

                let chunks = [
                    "Streaming list update chunk 1 keeps the history preview stable while the list is moving.\n",
                    "Streaming list update chunk 2 adds more text without forcing the row order to churn.\n",
                    "Streaming list update chunk 3 finishes the background reply after several scroll gestures."
                ]

                for chunk in chunks {
                    guard Task.isCancelled == false else {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: 350_000_000)
                    continuation.yield(.answerDelta(chunk))
                }

                continuation.finish()
            }
        }
    }
}

private struct UITestReplyCompletionStreamingService: AIStreamingService {
    func streamReply(for conversation: ConversationThread) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.thoughtDelta("Preparing a deterministic long reply for completion-anchor verification."))

                let chunks = [
                    "Reply Start Marker\n\nSection 1 explains the setup and deliberately stays near the start of the bubble.\n\n",
                    Array(
                        repeating: "Middle section keeps the final assistant bubble tall enough that anchoring to the end would hide the first lines after completion.\n",
                        count: 12
                    ).joined(separator: "\n"),
                    "\nReply End Marker"
                ]

                for chunk in chunks {
                    guard Task.isCancelled == false else {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continuation.yield(.answerDelta(chunk))
                }

                continuation.finish()
            }
        }
    }
}
#endif
#endif
