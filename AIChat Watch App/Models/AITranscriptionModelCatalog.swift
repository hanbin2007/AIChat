//
//  AITranscriptionModelCatalog.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/8.
//

import Foundation

nonisolated struct AITranscriptionModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String
    let subtitle: String
}

nonisolated enum AITranscriptionModelCatalog {
    static let builtInOptions: [AITranscriptionModelOption] = [
        AITranscriptionModelOption(
            id: "gemini-3-flash-preview",
            title: "Gemini 3 Flash",
            shortTitle: "Flash",
            subtitle: "Faster transcription"
        ),
        AITranscriptionModelOption(
            id: "gemini-3.1-pro-preview",
            title: "Gemini 3.1 Pro",
            shortTitle: "Pro",
            subtitle: "Higher quality transcription"
        )
    ]

    static func options(defaultModel: String) -> [AITranscriptionModelOption] {
        var options = builtInOptions

        if builtInOptions.contains(where: { $0.id == defaultModel }) == false {
            options.insert(
                AITranscriptionModelOption(
                    id: defaultModel,
                    title: defaultModel,
                    shortTitle: "Custom",
                    subtitle: "Configured default"
                ),
                at: 0
            )
        }

        return options
    }

    static func displayName(for model: String) -> String {
        option(for: model)?.title ?? model
    }

    static func shortLabel(for model: String) -> String {
        option(for: model)?.shortTitle ?? model
    }

    static func normalizedModel(_ model: String, defaultModel: String) -> String {
        options(defaultModel: defaultModel).contains(where: { $0.id == model }) ? model : defaultModel
    }

    private static func option(for model: String) -> AITranscriptionModelOption? {
        builtInOptions.first { $0.id == model }
    }
}
