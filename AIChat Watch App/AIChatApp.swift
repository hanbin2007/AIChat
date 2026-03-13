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
        }
    }
}

private enum UITestLaunchDestination: Equatable {
    case conversationDetail(UUID)
    case formulaHarness
}

private struct UITestBootstrap {
    let store: ChatStore
    let initialConversationID: UUID?
    let launchDestination: UITestLaunchDestination

    static func makeIfNeeded() -> UITestBootstrap? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIChat_UI_TEST_SCENARIO"] == "formula_zoom" else {
            return nil
        }

        return UITestBootstrap(
            store: ChatStore.previewStore(conversations: []),
            initialConversationID: nil,
            launchDestination: .formulaHarness
        )
    }
}
#endif
