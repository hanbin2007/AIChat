//
//  ConversationSettingsDraft.swift
//  AIChat Watch App
//
//  Shared conversation-settings draft logic used by watchOS and iOS.
//

import Foundation

struct ConversationSettingsDraft: Equatable {
    var title: String
    var systemPrompt: String

    private var persistedSystemPrompt: String

    init(title: String, systemPrompt: String) {
        self.title = title
        self.systemPrompt = systemPrompt
        self.persistedSystemPrompt = systemPrompt
    }

    var isSystemPromptDirty: Bool {
        systemPrompt != persistedSystemPrompt
    }

    func systemPromptSavePayload() -> String? {
        guard isSystemPromptDirty else {
            return nil
        }
        return systemPrompt
    }

    mutating func markSystemPromptSaved() {
        persistedSystemPrompt = systemPrompt
    }

    mutating func revertSystemPrompt() {
        systemPrompt = persistedSystemPrompt
    }
}
