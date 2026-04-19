//
//  SettingsServiceTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/4/12.
//

import Combine
import Foundation
import XCTest
@testable import AIChat_Watch_App

final class SettingsServiceTests: XCTestCase {
    @MainActor
    private func makeService(
        suiteName: String? = nil,
        fallbackModel: String = "gemini-3-flash-preview",
        fallbackTranscriptionModel: String = "gemini-3-flash-preview"
    ) -> (service: SettingsService, defaults: UserDefaults, suiteName: String) {
        let resolvedSuiteName = suiteName ?? "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: resolvedSuiteName)!
        let service = SettingsService(
            defaults: defaults,
            fallbackModel: fallbackModel,
            fallbackTranscriptionModel: fallbackTranscriptionModel
        )
        return (service, defaults, resolvedSuiteName)
    }

    @MainActor
    private func cleanUp(suiteName: String, defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Send Failure Retry Limit

    @MainActor
    func testDefaultSendFailureRetryLimitIsThree() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertEqual(service.sendFailureRetryLimit, 3)
    }

    @MainActor
    func testSendFailureRetryLimitClampsToSupportedBounds() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        service.updateSendFailureRetryLimit(99)
        XCTAssertEqual(service.sendFailureRetryLimit, 10)

        service.updateSendFailureRetryLimit(-2)
        XCTAssertEqual(service.sendFailureRetryLimit, 1)
    }

    @MainActor
    func testSendFailureRetryLimitPersistsAcrossRestart() {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        first.updateSendFailureRetryLimit(7)
        XCTAssertEqual(first.sendFailureRetryLimit, 7)

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertEqual(second.sendFailureRetryLimit, 7)
    }

    // MARK: - Default Conversation Configuration

    @MainActor
    func testDefaultConversationModelPersistsAcrossRestart() {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        first.updateDefaultConversationModel("gemini-3.1-pro-preview")
        XCTAssertEqual(first.defaultConversationConfiguration.model, "gemini-3.1-pro-preview")

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertEqual(second.defaultConversationConfiguration.model, "gemini-3.1-pro-preview")
    }

    @MainActor
    func testDefaultConversationThinkingIntensityNormalizesForModel() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        // Flash does not support .extreme — it should clamp to .deep
        service.updateDefaultConversationModel("gemini-3-flash-preview")
        service.updateDefaultConversationThinkingIntensity(.extreme)
        XCTAssertEqual(service.defaultConversationConfiguration.thinkingIntensity, .deep)

        // Pro supports .extreme
        service.updateDefaultConversationModel("gemini-3.1-pro-preview")
        service.updateDefaultConversationThinkingIntensity(.extreme)
        XCTAssertEqual(service.defaultConversationConfiguration.thinkingIntensity, .extreme)
    }

    @MainActor
    func testDefaultConversationSystemPromptTrimsWhitespace() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        service.updateDefaultConversationSystemPrompt("  Be concise.  ")
        XCTAssertEqual(service.defaultConversationConfiguration.customSystemPrompt, "Be concise.")
    }

    // MARK: - Global Auto Scroll

    @MainActor
    func testGlobalAutoScrollEnabledDefaultsToTrue() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertTrue(service.isGlobalAutoScrollEnabled)
    }

    @MainActor
    func testGlobalAutoScrollEnabledPersistsToggle() {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        first.updateGlobalAutoScrollEnabled(false)
        XCTAssertFalse(first.isGlobalAutoScrollEnabled)

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertFalse(second.isGlobalAutoScrollEnabled)
    }

    // MARK: - Transcription

    @MainActor
    func testTranscriptionModelPersists() {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        first.updateTranscriptionModel("gemini-3.1-pro-preview")
        XCTAssertEqual(first.transcriptionModel, "gemini-3.1-pro-preview")

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertEqual(second.transcriptionModel, "gemini-3.1-pro-preview")
    }

    @MainActor
    func testTranscriptionCustomPromptPersists() {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        first.updateTranscriptionCustomPrompt("Names: Tokyo Skytree")
        XCTAssertEqual(first.transcriptionCustomPrompt, "Names: Tokyo Skytree")

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertEqual(second.transcriptionCustomPrompt, "Names: Tokyo Skytree")
    }

    @MainActor
    func testTranscriptionIncludesContextDefaultsToTrue() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertTrue(service.transcriptionIncludesContext)
    }

    // MARK: - objectWillChange

    @MainActor
    func testObjectWillChangeFiresOnPropertyUpdate() {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        var didFire = false
        let cancellable = service.objectWillChange.sink { _ in
            didFire = true
        }

        service.updateSendFailureRetryLimit(5)
        XCTAssertTrue(didFire)

        _ = cancellable
    }
}
