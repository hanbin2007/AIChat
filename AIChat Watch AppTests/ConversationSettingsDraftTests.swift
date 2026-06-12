//
//  ConversationSettingsDraftTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/6/12.
//

import XCTest
@testable import AIChat_Watch_App

final class ConversationSettingsDraftTests: XCTestCase {
    func testSystemPromptStartsCleanAndOnlyProducesSavePayloadWhenDirty() {
        var draft = ConversationSettingsDraft(
            title: "Trip planning",
            systemPrompt: "Be concise."
        )

        XCTAssertFalse(draft.isSystemPromptDirty)
        XCTAssertNil(draft.systemPromptSavePayload())

        draft.systemPrompt = "Be playful."

        XCTAssertTrue(draft.isSystemPromptDirty)
        XCTAssertEqual(draft.systemPromptSavePayload(), "Be playful.")
    }

    func testMarkSystemPromptSavedResetsDirtyBaseline() {
        var draft = ConversationSettingsDraft(
            title: "Trip planning",
            systemPrompt: "Be concise."
        )

        draft.systemPrompt = "Be playful."
        draft.markSystemPromptSaved()

        XCTAssertFalse(draft.isSystemPromptDirty)
        XCTAssertNil(draft.systemPromptSavePayload())
    }

    func testRevertSystemPromptRestoresLastPersistedValue() {
        var draft = ConversationSettingsDraft(
            title: "Trip planning",
            systemPrompt: "Be concise."
        )

        draft.systemPrompt = "Be playful."
        draft.revertSystemPrompt()

        XCTAssertEqual(draft.systemPrompt, "Be concise.")
        XCTAssertFalse(draft.isSystemPromptDirty)
    }
}
