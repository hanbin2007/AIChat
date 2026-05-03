//
//  AssistantMarkdownPrewarmKeyTests.swift
//  AIChat Watch AppTests
//
//  Pins the contract that ChatStore prewarms the markdown cache using
//  the SAME string AssistantMessageMarkdownView later looks up — i.e.
//  `ChatMessage.cleanedText`. If the two diverge, every render with a
//  non-trivial `modelResponseParts` payload misses the cache, falls
//  through to `preparedContent(for:)`, and re-opens the .task
//  cancellation race that surfaced as "stuck on rendering" (issue #24).
//

import XCTest
@testable import AIChat_Watch_App

final class AssistantMarkdownPrewarmKeyTests: XCTestCase {

    // NOTE: All tests here are `async throws` even when the logic doesn't
    // require it. The watchOS 26 test runner has a launch-race bug where
    // the first sync `@MainActor` test per process segfaults the app host
    // while async ones survive. Keeping every test async works around it.

    @MainActor
    func testCleanedTextPrefersMergedVisiblePartsOverRawText() async throws {
        // When `modelResponseParts` carries the visible body, the view
        // renders `cleanedText` — i.e. the merged visible part text,
        // trimmed — not raw `text`. Prewarm must agree.
        let parts: [GeminiPartPayload] = [
            GeminiPartPayload(text: "Hello "),
            GeminiPartPayload(text: "world", thought: false),
            GeminiPartPayload(text: "internal monologue", thought: true)
        ]

        let message = ChatMessage(
            role: .assistant,
            text: "stale buffered text",
            modelResponseParts: parts
        )

        XCTAssertEqual(message.cleanedText, "Hello world",
                       "Visible parts must win over raw text — and thought parts must be excluded.")
    }

    @MainActor
    func testCleanedTextFallsBackToTrimmedRawTextWhenPartsAbsent() async throws {
        // No structured parts → fall back to `text`, but still trim.
        // This is the case where prewarming with raw `snapshot.text`
        // *also* used to work; the fix preserves that path.
        let message = ChatMessage(
            role: .assistant,
            text: "  spaced reply\n",
            modelResponseParts: nil
        )

        XCTAssertEqual(message.cleanedText, "spaced reply")
    }

    @MainActor
    func testCleanedTextTrimsMergedOutputSoCacheKeyIsStable() async throws {
        // Whitespace differences between the streaming buffer and the
        // view's consumed text are a cache-miss vector. The trim in
        // `cleanedText` is what makes the prewarm key stable, so pin
        // it here — a future refactor that drops the trim would
        // silently regress this fix.
        let parts: [GeminiPartPayload] = [
            GeminiPartPayload(text: "  trimmed  ")
        ]

        let message = ChatMessage(
            role: .assistant,
            text: "ignored",
            modelResponseParts: parts
        )

        XCTAssertEqual(message.cleanedText, "trimmed")
    }
}
