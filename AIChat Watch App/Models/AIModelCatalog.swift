//
//  AIModelCatalog.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation

nonisolated struct AIModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String
    let subtitle: String

    init(
        id: String,
        title: String,
        shortTitle: String,
        subtitle: String
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.subtitle = subtitle
    }
}

nonisolated enum AIModelCatalog {
    static let builtInOptions: [AIModelOption] = LicensedModelCatalog.supportedModels.map { definition in
        AIModelOption(
            id: definition.id,
            title: definition.title,
            shortTitle: compactShortLabel(for: definition.id),
            subtitle: definition.subtitle
        )
    }

    static func quickOptions(defaultModel: String) -> [AIModelOption] {
        var options = builtInOptions

        if builtInOptions.contains(where: { $0.id == defaultModel }) == false {
            options.insert(customOption(for: defaultModel), at: 0)
        }

        return options
    }

    static func quickOptions(defaultModel: String, allowedModelIDs: Set<String>?) -> [AIModelOption] {
        let options = quickOptions(defaultModel: defaultModel)
        guard let allowedModelIDs else {
            return options
        }

        let filtered = options.filter { allowedModelIDs.contains($0.id) }
        return filtered.isEmpty ? options : filtered
    }

    static func option(for model: String) -> AIModelOption? {
        builtInOptions.first { $0.id == model }
    }

    static func displayName(for model: String) -> String {
        option(for: model)?.title ?? prettifiedModelName(for: model)
    }

    static func shortLabel(for model: String) -> String {
        option(for: model)?.shortTitle ?? prettifiedModelName(for: model)
    }

    static func usesThinkingLevel(model: String) -> Bool {
        model.hasPrefix("gemini-3")
    }

    static func supportsExtremeThinking(model: String) -> Bool {
        model.hasPrefix("gemini-3.1-pro")
    }

    static func availableThinkingIntensities(for model: String) -> [AIThinkingIntensity] {
        let standardOptions: [AIThinkingIntensity] = [.fast, .balanced, .deep]
        return supportsExtremeThinking(model: model) ? standardOptions + [.extreme] : standardOptions
    }

    static func normalizedThinkingIntensity(_ intensity: AIThinkingIntensity, for model: String) -> AIThinkingIntensity {
        guard intensity == .extreme, supportsExtremeThinking(model: model) == false else {
            return intensity
        }

        return .deep
    }

    static func maxOutputTokens(for model: String) -> Int {
        if model.hasPrefix("gemini-3") || model.hasPrefix("gemini-2.5") {
            return 65_536
        }

        return 8_192
    }

    private static func customOption(for model: String) -> AIModelOption {
        AIModelOption(
            id: model,
            title: prettifiedModelName(for: model),
            shortTitle: compactShortLabel(for: model),
            subtitle: L10n.tr("model.subtitle.configured_default")
        )
    }

    private static func compactShortLabel(for model: String) -> String {
        let lowercased = model.lowercased()

        if lowercased.contains("pro") {
            return "Pro"
        }

        if lowercased.contains("flash") {
            if let version = versionToken(in: lowercased) {
                return version == "3" ? "Flash" : version
            }

            return "Flash"
        }

        if let version = versionToken(in: lowercased) {
            return version
        }

        return L10n.tr("model.short.custom")
    }

    private static func versionToken(in model: String) -> String? {
        let pattern = /(\d+(?:\.\d+)?)/
        return model.firstMatch(of: pattern).map { String($0.output.1) }
    }

    private static func prettifiedModelName(for model: String) -> String {
        let compact = model
            .replacingOccurrences(of: "-preview", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in
                switch token.lowercased() {
                case "gemini":
                    return "Gemini"
                case "pro":
                    return "Pro"
                case "flash":
                    return "Flash"
                default:
                    return String(token)
                }
            }
            .joined(separator: " ")

        return compact.nonEmptyTrimmed ?? model
    }
}
