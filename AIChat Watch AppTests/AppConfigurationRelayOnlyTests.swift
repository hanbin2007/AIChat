import XCTest
@testable import AIChat_Watch_App

final class AppConfigurationRelayOnlyTests: XCTestCase {
    override func tearDown() {
        unsetenv("AI_BACKEND_MODE")
        unsetenv("GEMINI_API_KEY")
        unsetenv("AI_RELAY_BASE_URL")
        unsetenv("AI_RELAY_BEARER_TOKEN")
        super.tearDown()
    }

    func testLoadIgnoresLegacyDirectBackendModeEnvironment() async throws {
        setenv("AI_BACKEND_MODE", "direct", 1)
        setenv("GEMINI_API_KEY", "must-not-ship", 1)
        setenv("AI_RELAY_BASE_URL", "https://relay.example.test", 1)
        setenv("AI_RELAY_BEARER_TOKEN", "must-not-ship-admin-token", 1)

        let configuration = AppConfiguration.load()

        XCTAssertEqual(configuration.backendMode, .relay)
        XCTAssertTrue(configuration.isAIConfigured)
        XCTAssertNil(configuration.geminiAPIKey)
        XCTAssertNil(configuration.relayBearerToken)
    }

    @MainActor
    func testServiceFactoryAlwaysCreatesRelayClient() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: "unused-direct-key",
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: "test-token",
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )

        let service = AIServiceFactory.makeService(
            configuration: configuration,
            relayAccessRootURL: relayAccessRootURL
        )
        let client = try XCTUnwrap(service as? RelayAIClient)

        XCTAssertEqual(client.relayAccessRootURL, relayAccessRootURL)
    }

    @MainActor
    func testRuntimeServicesResolveRelayCredentialsFromRepositoryRootEntitlementCache() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = ConversationRepository(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        let snapshot = makeManagedRelaySnapshot()
        let state = EntitlementState(
            account: snapshot,
            lastVerifiedAt: Date(),
            localSpend: 0,
            pending: nil,
            lastError: nil
        )
        try EntitlementCache(directory: repository.resolvedRootURL).save(state)

        let services = AIServiceFactory.makeRuntimeServices(
            configuration: configuration,
            repository: repository
        )
        let client = try XCTUnwrap(services.streamingService as? RelayAIClient)
        let request = try client.makeStreamRequest(
            for: ConversationThread(messages: [ChatMessage(role: .user, text: "Hello")])
        )

        XCTAssertEqual(client.relayAccessRootURL, repository.resolvedRootURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(snapshot.keyValue)")
    }

    @MainActor
    func testRelayBearerTokenCanResolveFromExplicitAccessRoot() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = RelayAccessRepository(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        let status = makeManagedRelayAccessStatus()

        try await repository.saveStatus(status)

        XCTAssertEqual(
            configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL),
            status.key?.keyValue
        )
    }

    @MainActor
    func testRelayBearerTokenFallsBackToReadyEntitlementSnapshot() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let snapshot = makeManagedRelaySnapshot()
        let state = EntitlementState(
            account: snapshot,
            lastVerifiedAt: Date(),
            localSpend: 0,
            pending: nil,
            lastError: nil
        )
        try EntitlementCache(directory: relayAccessRootURL).save(state)

        XCTAssertEqual(
            configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL),
            snapshot.keyValue
        )
    }

    @MainActor
    func testClearedRelayAccessKeyDoesNotFallBackToEntitlementSnapshot() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = RelayAccessRepository(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        let snapshot = makeManagedRelaySnapshot()
        let state = EntitlementState(
            account: snapshot,
            lastVerifiedAt: Date(),
            localSpend: 0,
            pending: nil,
            lastError: nil
        )
        try EntitlementCache(directory: relayAccessRootURL).save(state)

        XCTAssertEqual(
            configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL),
            snapshot.keyValue
        )

        try await repository.clearStoredKey()

        XCTAssertNil(configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL))
    }

    @MainActor
    func testRelayBearerTokenDoesNotUseUnavailableEntitlementSnapshot() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let snapshot = makeManagedRelaySnapshot(
            creditExpiresAt: Date().addingTimeInterval(-60)
        )
        let state = EntitlementState(
            account: snapshot,
            lastVerifiedAt: Date(),
            localSpend: 0,
            pending: nil,
            lastError: nil
        )
        try EntitlementCache(directory: relayAccessRootURL).save(state)

        XCTAssertNil(configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL))
    }

    @MainActor
    func testClearingStoredRelayKeyRevokesEntitlementFallbackKey() async throws {
        let relayAccessRootURL = makeTemporaryRootURL(prefix: "RelayAccessRoot")
        let configuration = AppConfiguration(
            backendMode: .relay,
            geminiAPIKey: nil,
            geminiModel: "gemini-3-flash-preview",
            geminiTranscriptionModel: "gemini-3-flash-preview",
            relayBaseURL: URL(string: "https://relay.example.test"),
            relayBearerToken: nil,
            relayStreamPath: "v1/chat/stream",
            appGroupIdentifier: nil
        )
        let repository = RelayAccessRepository(
            configuration: configuration,
            rootURL: relayAccessRootURL
        )
        let status = makeManagedRelayAccessStatus()
        let snapshot = makeManagedRelaySnapshot()
        let state = EntitlementState(
            account: snapshot,
            lastVerifiedAt: Date(),
            localSpend: 0,
            pending: nil,
            lastError: nil
        )
        try await repository.saveStatus(status)
        try EntitlementCache(directory: relayAccessRootURL).save(state)

        XCTAssertEqual(
            configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL),
            status.key?.keyValue
        )

        try await repository.clearStoredKey()

        XCTAssertNil(configuration.resolvedRelayBearerToken(rootURL: relayAccessRootURL))
    }
}
