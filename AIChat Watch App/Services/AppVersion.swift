//
//  AppVersion.swift
//  AIChat Watch App
//
//  Created by Codex on 2026/3/10.
//

import Foundation

extension Bundle {
    var appVersionDescription: String {
        let marketingVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (marketingVersion?.nonEmptyTrimmed, buildVersion?.nonEmptyTrimmed) {
        case let (marketingVersion?, buildVersion?):
            return "v\(marketingVersion) (\(buildVersion))"
        case let (marketingVersion?, nil):
            return "v\(marketingVersion)"
        case let (nil, buildVersion?):
            return buildVersion
        default:
            return L10n.tr("app.version.unknown")
        }
    }
}
