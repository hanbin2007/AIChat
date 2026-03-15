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
        if let bootstrap = UITestBootstrap.makeIfNeeded() {
            _chatStore = StateObject(wrappedValue: bootstrap.store)
            initialConversationID = bootstrap.initialConversationID
            uiTestLaunchDestination = bootstrap.launchDestination
        } else {
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
        default:
            return nil
        }
    }
}
#endif
