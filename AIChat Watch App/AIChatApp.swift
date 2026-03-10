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

    init() {
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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(chatStore)
        }
    }
}
#endif
