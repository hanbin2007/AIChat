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

enum AIModelCatalog {
    static let builtInOptions: [AIModelOption] = [
        AIModelOption(
            id: "gemini-3-flash-preview",
            title: "Gemini 3 Flash",
            shortTitle: "3 Flash",
            subtitle: "Fast multimodal"
        ),
        AIModelOption(
            id: "gemini-3.1-pro-preview",
            title: "Gemini 3.1 Pro",
            shortTitle: "3.1 Pro",
            subtitle: "Deeper reasoning"
        ),
        AIModelOption(
            id: "gemini-2.5-flash",
            title: "Gemini 2.5 Flash",
            shortTitle: "2.5 F",
            subtitle: "Stable fallback"
        )
    ]

    static func quickOptions(defaultModel: String) -> [AIModelOption] {
        var options = builtInOptions

        if builtInOptions.contains(where: { $0.id == defaultModel }) == false {
            options.insert(customOption(for: defaultModel), at: 0)
        }

        return options
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
            shortTitle: prettifiedModelName(for: model),
            subtitle: "Configured default"
        )
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
