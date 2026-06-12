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

        let service = AIServiceFactory.makeService(configuration: configuration)

        XCTAssertTrue(service is RelayAIClient)
    }
}
