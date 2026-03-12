//
//  L10n.swift
//  AIChat
//
//  Created by Codex on 2026/3/11.
//

import Foundation

enum L10n {
    nonisolated static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    nonisolated static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
