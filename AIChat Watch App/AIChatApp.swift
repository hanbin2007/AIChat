//
//  AIChatApp.swift
//  AIChat Watch App
//
//  Created by zhb on 2026/3/7.
//

import SwiftUI

@main
struct AIChat_Watch_AppApp: App {
    @StateObject private var chatStore: ChatStore

    init() {
        let configuration = AppConfiguration.load()
        let repository = ConversationRepository()
        let service = GeminiAPIClient(configuration: configuration)
        _chatStore = StateObject(
            wrappedValue: ChatStore(
                repository: repository,
                aiService: service,
                configuration: configuration
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
