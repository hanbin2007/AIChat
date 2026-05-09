//
//  ConversationSettingsViewModel.swift
//  AIChat Watch App
//
//  Drives the per-conversation configuration screen — title, AI
//  configuration, focus state, memory items, pinned memories, and tool
//  toggles. Persists changes through `ConversationPersistence`.
//
//  All edits go through `replaceThread(_:)` so the in-memory snapshot
//  stays consistent with persistence; the view only reads
//  `conversation` and calls these setters.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConversationSettingsViewModel {
    private(set) var conversation: ConversationThread

    private let persistence: ConversationPersistence

    init(conversation: ConversationThread, persistence: ConversationPersistence) {
        self.conversation = conversation
        self.persistence = persistence
    }

    // MARK: - Title

    func setTitle(_ title: String) async {
        var updated = conversation
        updated.updateTitle(title)
        await replaceThread(updated)
    }

    // MARK: - AI configuration

    func setAIConfiguration(_ configuration: ConversationAIConfiguration) async {
        var updated = conversation
        updated.updateAIConfiguration(configuration)
        await replaceThread(updated)
    }

    func setUsesGoogleSearch(_ enabled: Bool) async {
        var configuration = currentConfiguration
        configuration.usesGoogleSearch = enabled
        await setAIConfiguration(configuration)
    }

    func setUsesCodeExecution(_ enabled: Bool) async {
        var configuration = currentConfiguration
        configuration.usesCodeExecution = enabled
        await setAIConfiguration(configuration)
    }

    func setUsesGlobalPinnedMemory(_ enabled: Bool) async {
        var configuration = currentConfiguration
        configuration.usesGlobalPinnedMemory = enabled
        await setAIConfiguration(configuration)
    }

    func setThinkingIntensity(_ intensity: AIThinkingIntensity) async {
        var configuration = currentConfiguration
        configuration.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            intensity,
            for: configuration.model
        )
        await setAIConfiguration(configuration)
    }

    func setModel(_ model: String) async {
        var configuration = currentConfiguration
        configuration.model = model
        configuration.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            configuration.thinkingIntensity,
            for: model
        )
        await setAIConfiguration(configuration)
    }

    func setCustomSystemPrompt(_ text: String) async {
        var configuration = currentConfiguration
        configuration.customSystemPrompt = text.nonEmptyTrimmed
        await setAIConfiguration(configuration)
    }

    // MARK: - Focus state

    func setFocusState(_ state: ConversationFocusState?) async {
        var updated = conversation
        updated.updateFocusState(state)
        await replaceThread(updated)
    }

    // MARK: - Memory items

    func addMemoryItem(text: String, keywords: [String] = []) async {
        let item = ConversationMemoryItem(text: text, keywords: keywords)
        guard !item.text.isEmpty else { return }
        var updated = conversation
        updated.replaceMemoryItems(updated.memoryItems + [item])
        await replaceThread(updated)
    }

    func updateMemoryItem(_ item: ConversationMemoryItem) async {
        var updated = conversation
        var items = updated.memoryItems
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        updated.replaceMemoryItems(items)
        await replaceThread(updated)
    }

    func removeMemoryItem(id: UUID) async {
        var updated = conversation
        updated.replaceMemoryItems(updated.memoryItems.filter { $0.id != id })
        await replaceThread(updated)
    }

    // MARK: - Pinned memories (conversation scope)

    func addPinnedMemory(text: String, keywords: [String] = []) async {
        let item = PinnedMemoryItem(text: text, keywords: keywords, scope: .conversation)
        guard !item.text.isEmpty else { return }
        var updated = conversation
        updated.replacePinnedMemories(updated.pinnedMemories + [item])
        await replaceThread(updated)
    }

    func updatePinnedMemory(_ item: PinnedMemoryItem) async {
        var updated = conversation
        var items = updated.pinnedMemories
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        updated.replacePinnedMemories(items)
        await replaceThread(updated)
    }

    func removePinnedMemory(id: UUID) async {
        var updated = conversation
        updated.replacePinnedMemories(updated.pinnedMemories.filter { $0.id != id })
        await replaceThread(updated)
    }

    // MARK: - Archive (read-only browsing for now)

    var archiveSegments: [ConversationArchiveSegment] {
        conversation.archiveSegments
    }

    func clearArchive() async {
        var updated = conversation
        updated.replaceArchiveSegments([])
        await replaceThread(updated)
    }

    // MARK: - Helpers

    private var currentConfiguration: ConversationAIConfiguration {
        conversation.aiConfiguration ?? ConversationAIConfiguration(model: "gemini-3-flash-preview")
    }

    private func replaceThread(_ updated: ConversationThread) async {
        do {
            let persisted = try await persistence.upsert(updated)
            conversation = persisted
        } catch {
            // Keep the in-memory edit; persistence failures surface
            // through future error channels (out of scope here).
        }
    }
}
