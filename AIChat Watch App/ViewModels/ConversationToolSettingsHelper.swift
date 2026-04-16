//
//  ConversationToolSettingsHelper.swift
//  AIChat Watch App
//
//  Shared tool-settings logic used by both ConversationDetailView (watchOS)
//  and CompanionConversationDetailView (iOS).
//

import SwiftUI

struct ToolSettingsDraft: Equatable {
    var usesGoogleSearch: Bool
    var usesCodeExecution: Bool
}

@MainActor
enum ConversationToolSettingsHelper {

    static func googleSearchEnabledBinding(
        draft: Binding<ToolSettingsDraft?>,
        conversationID: UUID,
        chatStore: ChatStore
    ) -> Binding<Bool> {
        Binding(
            get: {
                draft.wrappedValue?.usesGoogleSearch
                    ?? chatStore.conversation(id: conversationID)?
                        .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
                        .usesGoogleSearch
                    ?? false
            },
            set: { newValue in
                ensureDraft(draft: draft, conversationID: conversationID, chatStore: chatStore)
                draft.wrappedValue?.usesGoogleSearch = newValue
            }
        )
    }

    static func codeExecutionEnabledBinding(
        draft: Binding<ToolSettingsDraft?>,
        conversationID: UUID,
        chatStore: ChatStore
    ) -> Binding<Bool> {
        Binding(
            get: {
                draft.wrappedValue?.usesCodeExecution
                    ?? chatStore.conversation(id: conversationID)?
                        .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
                        .usesCodeExecution
                    ?? false
            },
            set: { newValue in
                ensureDraft(draft: draft, conversationID: conversationID, chatStore: chatStore)
                draft.wrappedValue?.usesCodeExecution = newValue
            }
        )
    }

    static func presentToolSettings(
        draft: Binding<ToolSettingsDraft?>,
        isShowing: Binding<Bool>,
        conversationID: UUID,
        chatStore: ChatStore
    ) {
        ensureDraft(draft: draft, conversationID: conversationID, chatStore: chatStore)
        isShowing.wrappedValue = true
    }

    static func commitToolSettingsDraft(
        draft: Binding<ToolSettingsDraft?>,
        conversationID: UUID,
        chatStore: ChatStore
    ) async {
        guard let settingsDraft = draft.wrappedValue else {
            return
        }

        let currentConfig = chatStore.conversation(id: conversationID)?
            .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)

        let searchChanged = settingsDraft.usesGoogleSearch != (currentConfig?.usesGoogleSearch ?? false)
        let codeChanged = settingsDraft.usesCodeExecution != (currentConfig?.usesCodeExecution ?? false)

        if searchChanged {
            await chatStore.updateGoogleSearchEnabled(
                settingsDraft.usesGoogleSearch,
                for: conversationID
            )
        }

        if codeChanged {
            await chatStore.updateCodeExecutionEnabled(
                settingsDraft.usesCodeExecution,
                for: conversationID
            )
        }

        draft.wrappedValue = nil
    }

    static func toolButtonSymbols(
        draft: ToolSettingsDraft?,
        conversationID: UUID,
        chatStore: ChatStore
    ) -> [String] {
        let config = chatStore.conversation(id: conversationID)?
            .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
        let search = draft?.usesGoogleSearch ?? config?.usesGoogleSearch ?? false
        let code = draft?.usesCodeExecution ?? config?.usesCodeExecution ?? false

        var symbols: [String] = []
        if search { symbols.append("globe") }
        if code { symbols.append("chevron.left.forwardslash.chevron.right") }
        return symbols
    }

    static func toolButtonTint(symbols: [String]) -> Color {
        symbols.isEmpty ? .secondary : .cyan
    }

    static func toolButtonAccessibilityLabel(
        draft: ToolSettingsDraft?,
        conversationID: UUID,
        chatStore: ChatStore
    ) -> String {
        let config = chatStore.conversation(id: conversationID)?
            .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
        let search = draft?.usesGoogleSearch ?? config?.usesGoogleSearch ?? false
        let code = draft?.usesCodeExecution ?? config?.usesCodeExecution ?? false

        var parts: [String] = ["Tools"]
        if search { parts.append("Search on") }
        if code { parts.append("Code on") }
        return parts.joined(separator: ", ")
    }

    static func toolButtonAccessibilityValue(
        draft: ToolSettingsDraft?,
        conversationID: UUID,
        chatStore: ChatStore
    ) -> String {
        let config = chatStore.conversation(id: conversationID)?
            .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
        let search = draft?.usesGoogleSearch ?? config?.usesGoogleSearch ?? false
        let code = draft?.usesCodeExecution ?? config?.usesCodeExecution ?? false

        if search && code { return "Search and Code" }
        if search { return "Search" }
        if code { return "Code" }
        return "None"
    }

    // MARK: - Private

    private static func ensureDraft(
        draft: Binding<ToolSettingsDraft?>,
        conversationID: UUID,
        chatStore: ChatStore
    ) {
        guard draft.wrappedValue == nil else { return }
        let config = chatStore.conversation(id: conversationID)?
            .resolvedAIConfiguration(defaultModel: chatStore.configuration.geminiModel)
        draft.wrappedValue = ToolSettingsDraft(
            usesGoogleSearch: config?.usesGoogleSearch ?? false,
            usesCodeExecution: config?.usesCodeExecution ?? false
        )
    }
}
