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

    /// Verify that mutating `mutate` on a `SettingsService` is observable via
    /// `read` after re-instantiating the service against the same UserDefaults
    /// suite — i.e. that the value round-trips through persistence.
    @MainActor
    private func assertPersistsAcrossRestart<Value: Equatable>(
        mutate: (SettingsService) -> Void,
        read: (SettingsService) -> Value,
        expected: Value,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let suiteName = "AIChatTests.Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        mutate(first)
        XCTAssertEqual(read(first), expected, "first instance", file: file, line: line)

        let second = SettingsService(
            defaults: defaults,
            fallbackModel: "gemini-3-flash-preview",
            fallbackTranscriptionModel: "gemini-3-flash-preview"
        )
        XCTAssertEqual(read(second), expected, "after restart", file: file, line: line)
    }

    // MARK: - Send Failure Retry Limit

    @MainActor
    func testDefaultSendFailureRetryLimitIsThree() async throws {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertEqual(service.sendFailureRetryLimit, 3)
    }

    @MainActor
    func testSendFailureRetryLimitClampsToSupportedBounds() async throws {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        service.updateSendFailureRetryLimit(99)
        XCTAssertEqual(service.sendFailureRetryLimit, 10)

        service.updateSendFailureRetryLimit(-2)
        XCTAssertEqual(service.sendFailureRetryLimit, 1)
    }

    @MainActor
    func testSendFailureRetryLimitPersistsAcrossRestart() async throws {
        assertPersistsAcrossRestart(
            mutate: { $0.updateSendFailureRetryLimit(7) },
            read: { $0.sendFailureRetryLimit },
            expected: 7
        )
    }

    // MARK: - Default Conversation Configuration

    @MainActor
    func testDefaultConversationModelPersistsAcrossRestart() async throws {
        assertPersistsAcrossRestart(
            mutate: { $0.updateDefaultConversationModel("gemini-3.1-pro-preview") },
            read: { $0.defaultConversationConfiguration.model },
            expected: "gemini-3.1-pro-preview"
        )
    }

    @MainActor
    func testDefaultConversationThinkingIntensityNormalizesForModel() async throws {
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
    func testDefaultConversationSystemPromptTrimsWhitespace() async throws {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        service.updateDefaultConversationSystemPrompt("  Be concise.  ")
        XCTAssertEqual(service.defaultConversationConfiguration.customSystemPrompt, "Be concise.")
    }

    // MARK: - Global Auto Scroll

    @MainActor
    func testGlobalAutoScrollEnabledDefaultsToTrue() async throws {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertTrue(service.isGlobalAutoScrollEnabled)
    }

    @MainActor
    func testGlobalAutoScrollEnabledPersistsToggle() async throws {
        assertPersistsAcrossRestart(
            mutate: { $0.updateGlobalAutoScrollEnabled(false) },
            read: { $0.isGlobalAutoScrollEnabled },
            expected: false
        )
    }

    // MARK: - Transcription

    @MainActor
    func testTranscriptionModelPersists() async throws {
        assertPersistsAcrossRestart(
            mutate: { $0.updateTranscriptionModel("gemini-3.1-pro-preview") },
            read: { $0.transcriptionModel },
            expected: "gemini-3.1-pro-preview"
        )
    }

    @MainActor
    func testTranscriptionCustomPromptPersists() async throws {
        assertPersistsAcrossRestart(
            mutate: { $0.updateTranscriptionCustomPrompt("Names: Tokyo Skytree") },
            read: { $0.transcriptionCustomPrompt },
            expected: "Names: Tokyo Skytree"
        )
    }

    @MainActor
    func testTranscriptionIncludesContextDefaultsToTrue() async throws {
        let (service, defaults, suiteName) = makeService()
        defer { cleanUp(suiteName: suiteName, defaults: defaults) }

        XCTAssertTrue(service.transcriptionIncludesContext)
    }

    // MARK: - objectWillChange

    @MainActor
    func testObjectWillChangeFiresOnPropertyUpdate() async throws {
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
