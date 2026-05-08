//
//  GlobalSettingsViewModel.swift
//  AIChat Watch App
//
//  Drives the app-wide settings screen — default conversation model,
//  transcription model, auto-scroll preference, and a read-only
//  glance at the current credit balance via `BillingViewModel`.
//

import Foundation
import Observation

@Observable
@MainActor
final class GlobalSettingsViewModel {
    private(set) var sendFailureRetryLimit: Int
    private(set) var isGlobalAutoScrollEnabled: Bool
    private(set) var defaultConversationConfiguration: ConversationAIConfiguration
    private(set) var transcriptionModel: String
    private(set) var transcriptionCustomPrompt: String
    private(set) var transcriptionIncludesContext: Bool

    private let settings: SettingsService

    init(settings: SettingsService) {
        self.settings = settings
        self.sendFailureRetryLimit = settings.sendFailureRetryLimit
        self.isGlobalAutoScrollEnabled = settings.isGlobalAutoScrollEnabled
        self.defaultConversationConfiguration = settings.defaultConversationConfiguration
        self.transcriptionModel = settings.transcriptionModel
        self.transcriptionCustomPrompt = settings.transcriptionCustomPrompt
        self.transcriptionIncludesContext = settings.transcriptionIncludesContext
    }

    func updateSendFailureRetryLimit(_ value: Int) {
        settings.updateSendFailureRetryLimit(value)
        sendFailureRetryLimit = settings.sendFailureRetryLimit
    }

    func updateGlobalAutoScroll(_ enabled: Bool) {
        settings.updateGlobalAutoScrollEnabled(enabled)
        isGlobalAutoScrollEnabled = settings.isGlobalAutoScrollEnabled
    }

    func updateDefaultConversationModel(_ model: String) {
        settings.updateDefaultConversationModel(model)
        defaultConversationConfiguration = settings.defaultConversationConfiguration
    }

    func updateDefaultThinkingIntensity(_ intensity: AIThinkingIntensity) {
        settings.updateDefaultConversationThinkingIntensity(intensity)
        defaultConversationConfiguration = settings.defaultConversationConfiguration
    }

    func updateDefaultSystemPrompt(_ prompt: String) {
        settings.updateDefaultConversationSystemPrompt(prompt)
        defaultConversationConfiguration = settings.defaultConversationConfiguration
    }

    func updateTranscriptionModel(_ model: String) {
        settings.updateTranscriptionModel(model)
        transcriptionModel = settings.transcriptionModel
    }

    func updateTranscriptionCustomPrompt(_ value: String) {
        settings.updateTranscriptionCustomPrompt(value)
        transcriptionCustomPrompt = settings.transcriptionCustomPrompt
    }

    func updateTranscriptionIncludesContext(_ enabled: Bool) {
        settings.updateTranscriptionIncludesContext(enabled)
        transcriptionIncludesContext = settings.transcriptionIncludesContext
    }
}
