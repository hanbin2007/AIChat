//
//  DraftTextComposer.swift
//  AIChat Watch App
//
//  Pure utility extracted from the deleted `ChatStore.swift`. Merges a
//  voice-transcription continuation into the existing compose-field
//  draft with locale-aware punctuation/separator handling (CJK joins
//  with `，`, Latin with a space, leading punctuation gets glued
//  directly).
//
//  Used by the future detail-view voice flow + already covered by
//  `ConversationSortingAndComposerTests`.
//

import Foundation

nonisolated enum DraftTextComposer {
    private static let sentencePunctuation = CharacterSet(charactersIn: ".?!。！？…")
    private static let clausePunctuation = CharacterSet(charactersIn: ",;:，；：")
    private static let leadingJoinPunctuation = CharacterSet(charactersIn: ".,;:!?%)]}，。！？；：、）】》」』'")

    static func appended(existing: String, addition: String) -> String {
        let normalizedAddition = normalizeSegment(addition)
        guard normalizedAddition.isEmpty == false else {
            return existing
        }

        let normalizedExisting = existing.trimmed
        guard normalizedExisting.isEmpty == false else {
            return normalizedAddition
        }

        return normalizedExisting + separatorBetween(existing: normalizedExisting, addition: normalizedAddition) + normalizedAddition
    }

    private static func normalizeSegment(_ text: String) -> String {
        text
            .collapseWhitespace()
            .replacingOccurrences(of: "\\s+([，。！？；：,.!?;:])", with: "$1", options: .regularExpression)
            .trimmed
    }

    private static func separatorBetween(existing: String, addition: String) -> String {
        guard let existingScalar = existing.unicodeScalars.last,
              let additionScalar = addition.unicodeScalars.first
        else {
            return " "
        }

        if CharacterSet.newlines.contains(existingScalar) || CharacterSet.newlines.contains(additionScalar) {
            return ""
        }

        if leadingJoinPunctuation.contains(additionScalar) {
            return ""
        }

        if sentencePunctuation.contains(existingScalar) || clausePunctuation.contains(existingScalar) {
            return needsInterWordSpace(before: existingScalar, after: additionScalar) ? " " : ""
        }

        if isCJK(existingScalar) && isCJK(additionScalar) {
            return "，"
        }

        return needsInterWordSpace(before: existingScalar, after: additionScalar) ? " " : ""
    }

    private static func needsInterWordSpace(
        before existingScalar: UnicodeScalar,
        after additionScalar: UnicodeScalar
    ) -> Bool {
        isLatinLike(existingScalar) && isLatinLike(additionScalar)
    }

    private static func isLatinLike(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FDF,
             0x3040...0x30FF,
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0xFF66...0xFF9F:
            return true
        default:
            return false
        }
    }
}
