//
//  AppConfiguration.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/7.
//

import Foundation

struct AppConfiguration: Equatable {
    let geminiAPIKey: String?
    let geminiModel: String

    static func load(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        let environment = processInfo.environment

        let envAPIKey = environment["GEMINI_API_KEY"]?.nonEmptyTrimmed
        let plistAPIKey = (bundle.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String)?.nonEmptyTrimmed
        let envModel = environment["GEMINI_MODEL"]?.nonEmptyTrimmed
        let plistModel = (bundle.object(forInfoDictionaryKey: "GEMINI_MODEL") as? String)?.nonEmptyTrimmed

        return AppConfiguration(
            geminiAPIKey: envAPIKey ?? plistAPIKey,
            geminiModel: envModel ?? plistModel ?? "gemini-2.0-flash"
        )
    }

    var isGeminiConfigured: Bool {
        geminiAPIKey != nil
    }

    var configurationMessage: String {
        if isGeminiConfigured {
            return "Gemini is ready."
        }

        return "Set GEMINI_API_KEY in the scheme environment or Info.plist before sending messages."
    }
}
