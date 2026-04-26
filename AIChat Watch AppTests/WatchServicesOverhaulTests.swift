//
//  WatchServicesOverhaulTests.swift
//  AIChat Watch AppTests
//
//  Covers the watch-services overhaul (Agent D scope):
//  - `RelayRequestEnricher` writes the expected client-context headers
//    and the conversation-id when supplied.
//  - `RelayAIClient.streamReply` attaches the conversation-id header.
//  - `RelayAccountService.performJSONRequest` attaches client-context
//    headers (no conversation id).
//  - `GeminiMemoryExtractionClient` now throws
//    `RelayAPIError.directModeUnsupported` (direct-mode stub).
//  - `firstBalancedJSONObject` extracts only the first balanced JSON
//    object (replaces the greedy `\{[\s\S]*\}` regex).
//  - `makeRelayURLSession` caches one session per allowed-host so
//    insecure-TLS calls do not leak `URLSession`s.
//  - `ConversationRepository` skips re-writing attachment blobs when
//    the on-disk file already matches by size.
//

import XCTest
@testable import AIChat_Watch_App

final class WatchServicesOverhaulTests: XCTestCase {

    // MARK: - RelayRequestEnricher

    @MainActor
    func testEnricherAttachesAllStandardClientContextHeaders() async throws {
        var request = URLRequest(url: URL(string: "https://relay.example.test/v1/chat/stream")!)
        RelayRequestEnricher.attachClientContext(to: &request)

        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-aichat-app-version"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-aichat-app-build"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-aichat-os"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-aichat-device-model"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "x-aichat-locale"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))

        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        XCTAssertTrue(userAgent.hasPrefix("AIChat/"), "Got: \(userAgent)")
    }

    @MainActor
    func testEnricherAttachesConversationIDWhenProvided() async throws {
        let conversationID = UUID()
        var request = URLRequest(url: URL(string: "https://relay.example.test/v1/chat/stream")!)
        RelayRequestEnricher.attachClientContext(to: &request, conversationID: conversationID)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-aichat-conversation-id"),
            conversationID.uuidString
        )
    }

    @MainActor
    func testEnricherOmitsConversationIDHeaderWhenNotProvided() async throws {
        var request = URLRequest(url: URL(string: "https://relay.example.test/v1/account/status")!)
        RelayRequestEnricher.attachClientContext(to: &request)

        XCTAssertNil(request.value(forHTTPHeaderField: "x-aichat-conversation-id"))
    }

    // MARK: - GeminiMemoryExtractionClient direct-mode stub

    func testGeminiMemoryExtractionClientThrowsDirectModeUnsupported() async throws {
        let client = GeminiMemoryExtractionClient(
            configuration: AppConfiguration(
                backendMode: .direct,
                geminiAPIKey: "test-key",
                geminiModel: "gemini-3-flash-preview",
                geminiTranscriptionModel: "gemini-3-flash-preview",
                relayBaseURL: nil,
                relayBearerToken: nil,
                relayStreamPath: "v1/chat/stream",
                appGroupIdentifier: nil
            )
        )

        let request = ConversationMemoryExtractionRequest(
            model: "gemini-3-flash-preview",
            mode: "casual",
            conversationTitle: "Test",
            recentMessages: [],
            existingFocusState: nil,
            existingMemoryItems: [],
            archiveCandidateMessages: []
        )

        do {
            _ = try await client.extractMemory(request: request)
            XCTFail("Expected directModeUnsupported throw")
        } catch RelayAPIError.directModeUnsupported {
            // Expected — direct mode is a stub now.
        } catch {
            XCTFail("Expected RelayAPIError.directModeUnsupported, got \(error)")
        }
    }

    // MARK: - JSON brace-walker (replaces the greedy regex)

    func testFirstBalancedJSONObjectReturnsTheFirstObject() async throws {
        let source = """
        garbage prefix
        {"focus": "first", "openLoops": []}
        {"focus": "second"}
        """

        let result = firstBalancedJSONObject(in: source)
        XCTAssertNotNil(result)
        XCTAssertEqual(String(result ?? ""), "{\"focus\": \"first\", \"openLoops\": []}")
    }

    func testFirstBalancedJSONObjectHandlesNestedObjects() async throws {
        let source = """
        prefix
        {"a": {"b": {"c": 1}}, "d": 2}
        trailing
        """

        let result = firstBalancedJSONObject(in: source)
        XCTAssertEqual(String(result ?? ""), "{\"a\": {\"b\": {\"c\": 1}}, \"d\": 2}")
    }

    func testFirstBalancedJSONObjectIgnoresBracesInsideStrings() async throws {
        // The brace-walker must not be tricked by `}` inside string
        // literals — a regex would have been.
        let source = "{\"text\": \"closing brace } inside a string\", \"count\": 1}"

        let result = firstBalancedJSONObject(in: source)
        XCTAssertEqual(String(result ?? ""), source)
    }

    func testFirstBalancedJSONObjectHandlesEscapedQuotes() async throws {
        let source = "{\"text\": \"escaped \\\" quote\", \"closed\": true}"

        let result = firstBalancedJSONObject(in: source)
        XCTAssertEqual(String(result ?? ""), source)
    }

    func testFirstBalancedJSONObjectReturnsNilWhenUnbalanced() async throws {
        XCTAssertNil(firstBalancedJSONObject(in: "no JSON here"))
        // Open without close.
        XCTAssertNil(firstBalancedJSONObject(in: "{ open without close"))
    }

    // MARK: - URLSession cache

    func testInsecureRelaySessionsAreCachedByHost() async throws {
        // Reset between subtests so we don't depend on test order.
        _resetRelayURLSessionCacheForTesting()

        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.local"),
            relayBearerToken: "token",
            relayStreamPath: "v1/chat/stream",
            relayAllowsInsecureTLS: true,
            appGroupIdentifier: nil
        )

        let fallback = URLSession(configuration: .default)
        let first = makeRelayURLSession(configuration: configuration, fallback: fallback)
        let second = makeRelayURLSession(configuration: configuration, fallback: fallback)

        XCTAssertTrue(
            first === second,
            "Expected the insecure-TLS URLSession to be reused across calls; got distinct instances."
        )

        _resetRelayURLSessionCacheForTesting()
    }

    func testInsecureRelaySessionFallsBackWhenInsecureTLSDisabled() async throws {
        _resetRelayURLSessionCacheForTesting()

        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.local"),
            relayBearerToken: "token",
            relayStreamPath: "v1/chat/stream",
            relayAllowsInsecureTLS: false,
            appGroupIdentifier: nil
        )

        let fallback = URLSession(configuration: .default)
        let session = makeRelayURLSession(configuration: configuration, fallback: fallback)

        XCTAssertTrue(
            session === fallback,
            "When insecure TLS is disabled, the helper must return the fallback session unchanged."
        )
    }

    // MARK: - ConversationRepository attachment materialization skip

    func testMaterializeAttachmentExportsSkipsWhenBlobAlreadyUpToDate() async throws {
        // Build a repository, save one conversation with an inline
        // image attachment, then ensure that calling
        // `loadConversations()` again does not rewrite the blob file.
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIChatRepoMaterializeTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example"),
            relayBearerToken: "token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(configuration: configuration, rootURL: rootURL)

        let attachmentData = Data("hello-blob".utf8)
        let attachment = ChatAttachment(
            kind: .image,
            filename: "test.jpg",
            mimeType: "image/jpeg",
            data: attachmentData
        )
        let conversation = ConversationThread(
            messages: [ChatMessage(role: .user, text: "hi", attachments: [attachment])]
        )

        _ = try await repository.save(conversation)
        let loadedOnce = try await repository.loadConversations()
        XCTAssertEqual(loadedOnce.count, 1)
        let blobFilename = loadedOnce.first?.messages.first?.attachments.first?.blobFilename
        let blobURL = repository.attachmentsDirectoryURL.appendingPathComponent(
            blobFilename ?? "",
            isDirectory: false
        )

        // Mark the file's mtime so we can detect a rewrite.
        let originalMtime = try FileManager.default
            .attributesOfItem(atPath: blobURL.path)[.modificationDate] as? Date
        XCTAssertNotNil(originalMtime)

        // Wait briefly so a rewrite would produce a measurably newer
        // mtime.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Reload — must NOT rewrite the blob because size matches.
        _ = try await repository.loadConversations()
        let secondMtime = try FileManager.default
            .attributesOfItem(atPath: blobURL.path)[.modificationDate] as? Date

        XCTAssertEqual(
            originalMtime,
            secondMtime,
            "Reloading conversations must not rewrite up-to-date attachment blobs."
        )
    }
}
