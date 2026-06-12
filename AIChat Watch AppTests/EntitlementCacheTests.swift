import XCTest
@testable import AIChat_Watch_App

final class EntitlementCacheTests: XCTestCase {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testSaveThenLoadRoundTrips() async throws {
        let cache = EntitlementCache(directory: try tempDir())
        var state = EntitlementState()
        state.localSpend = 42
        try cache.save(state)
        XCTAssertEqual(cache.load()?.localSpend, 42)
    }

    func testLoadMissingReturnsNil() async throws {
        XCTAssertNil(EntitlementCache(directory: try tempDir()).load())
    }

    func testLoadWrongSchemaReturnsNil() async throws {
        let cache = EntitlementCache(directory: try tempDir())
        // Write a state file with a wrong schemaVersion, bypassing save() (which forces the current version).
        var state = EntitlementState()
        state.schemaVersion = 999
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: cache.cacheDirectoryURL, withIntermediateDirectories: true)
        try data.write(to: cache.fileURL)
        XCTAssertNil(cache.load())
    }

    func testClearRemovesFile() async throws {
        let cache = EntitlementCache(directory: try tempDir())
        try cache.save(EntitlementState())
        try cache.clear()
        XCTAssertNil(cache.load())
    }
}
