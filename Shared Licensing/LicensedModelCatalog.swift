//
//  LicensedModelCatalog.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import Foundation

nonisolated struct LicensedModelDefinition: Identifiable, Equatable, Hashable, Sendable {
    let bitIndex: Int
    let id: String
    let title: String
    let subtitle: String

    var bitMask: UInt16 {
        1 << bitIndex
    }
}

nonisolated enum LicensedModelCatalog {
    static let supportedModels: [LicensedModelDefinition] = [
        LicensedModelDefinition(
            bitIndex: 0,
            id: "gemini-3-flash-preview",
            title: "Gemini 3 Flash",
            subtitle: L10n.tr("licensed_model.subtitle.fast_multimodal")
        ),
        LicensedModelDefinition(
            bitIndex: 1,
            id: "gemini-3.1-pro-preview",
            title: "Gemini 3.1 Pro",
            subtitle: L10n.tr("licensed_model.subtitle.deeper_reasoning")
        ),
        LicensedModelDefinition(
            bitIndex: 2,
            id: "gemini-2.5-flash",
            title: "Gemini 2.5 Flash",
            subtitle: L10n.tr("licensed_model.subtitle.stable_fallback")
        )
    ]

    static let unrestrictedMask: UInt16 = 0

    static func mask(for modelIDs: Set<String>?) -> UInt16 {
        guard let modelIDs, modelIDs.isEmpty == false else {
            return unrestrictedMask
        }

        return supportedModels.reduce(into: UInt16.zero) { partialResult, model in
            if modelIDs.contains(model.id) {
                partialResult |= model.bitMask
            }
        }
    }

    static func modelIDs(for mask: UInt16) -> Set<String>? {
        guard mask != unrestrictedMask else {
            return nil
        }

        let resolved = Set(
            supportedModels
                .filter { mask & $0.bitMask != 0 }
                .map(\.id)
        )

        return resolved.isEmpty ? nil : resolved
    }

    static func isAllowed(modelID: String, mask: UInt16) -> Bool {
        guard mask != unrestrictedMask else {
            return true
        }

        guard let model = supportedModels.first(where: { $0.id == modelID }) else {
            return false
        }

        return mask & model.bitMask != 0
    }

    static func firstAllowedModelID(preferredOrder: [String]? = nil, mask: UInt16) -> String? {
        let candidates = preferredOrder ?? supportedModels.map(\.id)
        for candidate in candidates where isAllowed(modelID: candidate, mask: mask) {
            return candidate
        }

        return supportedModels.first(where: { isAllowed(modelID: $0.id, mask: mask) })?.id
    }
}
