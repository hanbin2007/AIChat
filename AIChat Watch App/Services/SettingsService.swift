//
//  SettingsService.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/4/12.
//

import Combine
import Foundation

@MainActor
final class SettingsService: ObservableObject {
    static let defaultSendFailureRetryLimit = 3
    static let maximumSendFailureRetryLimit = 10
    static let minimumSendFailureRetryLimit = 1

    @Published private(set) var sendFailureRetryLimit: Int
    @Published private(set) var isGlobalAutoScrollEnabled: Bool
    @Published private(set) var defaultConversationConfiguration: ConversationAIConfiguration
    @Published private(set) var transcriptionModel: String
    @Published private(set) var transcriptionCustomPrompt: String
    @Published private(set) var transcriptionIncludesContext: Bool

    private let defaults: UserDefaults
    private let fallbackModel: String
    private let fallbackTranscriptionModel: String

    init(
        defaults: UserDefaults,
        fallbackModel: String,
        fallbackTranscriptionModel: String
    ) {
        self.defaults = defaults
        self.fallbackModel = fallbackModel
        self.fallbackTranscriptionModel = fallbackTranscriptionModel
        self.sendFailureRetryLimit = Self.loadSendFailureRetryLimit(from: defaults)
        self.isGlobalAutoScrollEnabled = Self.loadGlobalAutoScrollEnabled(from: defaults)
        self.defaultConversationConfiguration = Self.loadDefaultConversationConfiguration(
            from: defaults,
            fallbackModel: fallbackModel
        )
        self.transcriptionModel = Self.loadTranscriptionModel(
            from: defaults,
            fallbackModel: fallbackTranscriptionModel
        )
        self.transcriptionCustomPrompt = Self.loadTranscriptionCustomPrompt(from: defaults)
        self.transcriptionIncludesContext = Self.loadTranscriptionIncludesContext(from: defaults)
    }

    func updateSendFailureRetryLimit(_ limit: Int) {
        let normalizedLimit = Self.normalizedSendFailureRetryLimit(limit)
        guard normalizedLimit != sendFailureRetryLimit else {
            return
        }

        sendFailureRetryLimit = normalizedLimit
        defaults.set(normalizedLimit, forKey: DefaultsKeys.sendFailureRetryLimit)
    }

    func updateGlobalAutoScrollEnabled(_ enabled: Bool) {
        guard isGlobalAutoScrollEnabled != enabled else {
            return
        }

        isGlobalAutoScrollEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKeys.globalAutoScrollEnabled)
    }

    func updateDefaultConversationModel(_ model: String) {
        let normalizedThinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            defaultConversationConfiguration.thinkingIntensity,
            for: model
        )

        guard defaultConversationConfiguration.model != model ||
                defaultConversationConfiguration.thinkingIntensity != normalizedThinkingIntensity
        else {
            return
        }

        defaultConversationConfiguration.model = model
        defaultConversationConfiguration.thinkingIntensity = normalizedThinkingIntensity
        persistDefaultConversationConfiguration()
    }

    func updateDefaultConversationThinkingIntensity(_ thinkingIntensity: AIThinkingIntensity) {
        let normalizedThinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            thinkingIntensity,
            for: defaultConversationConfiguration.model
        )

        guard defaultConversationConfiguration.thinkingIntensity != normalizedThinkingIntensity else {
            return
        }

        defaultConversationConfiguration.thinkingIntensity = normalizedThinkingIntensity
        persistDefaultConversationConfiguration()
    }

    func updateDefaultConversationSystemPrompt(_ prompt: String) {
        let normalizedPrompt = prompt.nonEmptyTrimmed
        guard defaultConversationConfiguration.customSystemPrompt != normalizedPrompt else {
            return
        }

        defaultConversationConfiguration.customSystemPrompt = normalizedPrompt
        persistDefaultConversationConfiguration()
    }

    func updateTranscriptionModel(_ model: String) {
        let normalizedModel = AITranscriptionModelCatalog.normalizedModel(
            model,
            defaultModel: fallbackTranscriptionModel
        )
        guard normalizedModel != transcriptionModel else {
            return
        }

        transcriptionModel = normalizedModel
        defaults.set(normalizedModel, forKey: DefaultsKeys.transcriptionModel)
    }

    func updateTranscriptionCustomPrompt(_ prompt: String) {
        let normalizedPrompt = prompt
        guard transcriptionCustomPrompt != normalizedPrompt else {
            return
        }

        transcriptionCustomPrompt = normalizedPrompt
        defaults.set(normalizedPrompt, forKey: DefaultsKeys.transcriptionCustomPrompt)
    }

    func updateTranscriptionIncludesContext(_ includesContext: Bool) {
        guard transcriptionIncludesContext != includesContext else {
            return
        }

        transcriptionIncludesContext = includesContext
        defaults.set(includesContext, forKey: DefaultsKeys.transcriptionIncludesContext)
    }

    // MARK: - Persistence

    private func persistDefaultConversationConfiguration() {
        defaults.set(defaultConversationConfiguration.model, forKey: DefaultsKeys.defaultConversationModel)
        defaults.set(
            defaultConversationConfiguration.thinkingIntensity.rawValue,
            forKey: DefaultsKeys.defaultConversationThinkingIntensity
        )
        defaults.set(
            defaultConversationConfiguration.customSystemPrompt ?? "",
            forKey: DefaultsKeys.defaultConversationSystemPrompt
        )
    }

    // MARK: - Static Loaders

    static func normalizedSendFailureRetryLimit(_ value: Int) -> Int {
        min(max(value, minimumSendFailureRetryLimit), maximumSendFailureRetryLimit)
    }

    private static func loadSendFailureRetryLimit(from defaults: UserDefaults) -> Int {
        let storedValue = defaults.object(forKey: DefaultsKeys.sendFailureRetryLimit) as? Int
        let resolvedValue = storedValue ?? defaultSendFailureRetryLimit
        let normalizedValue = normalizedSendFailureRetryLimit(resolvedValue)

        defaults.set(normalizedValue, forKey: DefaultsKeys.sendFailureRetryLimit)
        return normalizedValue
    }

    private static func loadGlobalAutoScrollEnabled(from defaults: UserDefaults) -> Bool {
        let enabled: Bool

        if defaults.object(forKey: DefaultsKeys.globalAutoScrollEnabled) == nil {
            enabled = true
        } else {
            enabled = defaults.bool(forKey: DefaultsKeys.globalAutoScrollEnabled)
        }

        defaults.set(enabled, forKey: DefaultsKeys.globalAutoScrollEnabled)
        return enabled
    }

    static func loadDefaultConversationConfiguration(
        from defaults: UserDefaults,
        fallbackModel: String
    ) -> ConversationAIConfiguration {
        let model = defaults.string(forKey: DefaultsKeys.defaultConversationModel)?.nonEmptyTrimmed ?? fallbackModel
        let storedThinkingIntensity = defaults.string(forKey: DefaultsKeys.defaultConversationThinkingIntensity)
            .flatMap(AIThinkingIntensity.init(rawValue:))
        let thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
            storedThinkingIntensity ?? .balanced,
            for: model
        )
        let customSystemPrompt = defaults.string(forKey: DefaultsKeys.defaultConversationSystemPrompt)?.nonEmptyTrimmed

        defaults.set(model, forKey: DefaultsKeys.defaultConversationModel)
        defaults.set(thinkingIntensity.rawValue, forKey: DefaultsKeys.defaultConversationThinkingIntensity)
        defaults.set(customSystemPrompt ?? "", forKey: DefaultsKeys.defaultConversationSystemPrompt)

        return ConversationAIConfiguration(
            model: model,
            thinkingIntensity: thinkingIntensity,
            customSystemPrompt: customSystemPrompt
        )
    }

    private static func loadTranscriptionModel(
        from defaults: UserDefaults,
        fallbackModel: String
    ) -> String {
        let storedModel = defaults.string(forKey: DefaultsKeys.transcriptionModel)
        let resolvedModel = AITranscriptionModelCatalog.normalizedModel(
            storedModel ?? fallbackModel,
            defaultModel: fallbackModel
        )

        defaults.set(resolvedModel, forKey: DefaultsKeys.transcriptionModel)
        return resolvedModel
    }

    private static func loadTranscriptionCustomPrompt(from defaults: UserDefaults) -> String {
        let prompt = defaults.string(forKey: DefaultsKeys.transcriptionCustomPrompt) ?? ""
        defaults.set(prompt, forKey: DefaultsKeys.transcriptionCustomPrompt)
        return prompt
    }

    private static func loadTranscriptionIncludesContext(from defaults: UserDefaults) -> Bool {
        let includesContext: Bool

        if defaults.object(forKey: DefaultsKeys.transcriptionIncludesContext) == nil {
            includesContext = true
        } else {
            includesContext = defaults.bool(forKey: DefaultsKeys.transcriptionIncludesContext)
        }

        defaults.set(includesContext, forKey: DefaultsKeys.transcriptionIncludesContext)
        return includesContext
    }

    // MARK: - Defaults Keys

    enum DefaultsKeys {
        static let sendFailureRetryLimit = "chat.send_failure_retry_limit"
        static let globalAutoScrollEnabled = "chat.global_auto_scroll_enabled"
        static let defaultConversationModel = "chat.default_conversation_model"
        static let defaultConversationThinkingIntensity = "chat.default_conversation_thinking_intensity"
        static let defaultConversationSystemPrompt = "chat.default_conversation_system_prompt"
        static let transcriptionModel = "chat.transcription_model"
        static let transcriptionCustomPrompt = "chat.transcription_custom_prompt"
        static let transcriptionIncludesContext = "chat.transcription_includes_context"
    }
}
