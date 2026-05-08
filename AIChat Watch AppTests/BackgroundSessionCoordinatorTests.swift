//
//  BackgroundSessionCoordinatorTests.swift
//  AIChat Watch AppTests
//
//  Exercises the BackgroundSessionCoordinator with a stub
//  BackgroundSessionHandle so we don't depend on the real
//  WKExtendedRuntimeSession (unavailable / ineffective in tests).
//

import XCTest
@testable import AIChat_Watch_App

@MainActor
final class BackgroundSessionCoordinatorTests: XCTestCase {

    func test_beginCreatesAndStartsSession() async throws {
        let stub = StubBackgroundSessionHandle()
        let coordinator = BackgroundSessionCoordinator(factory: { stub })

        XCTAssertFalse(coordinator.isActive)
        coordinator.begin()
        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(stub.startCount, 1)
    }

    func test_beginIsIdempotentWhileActive() async throws {
        var creations = 0
        let coordinator = BackgroundSessionCoordinator(factory: {
            creations += 1
            return StubBackgroundSessionHandle()
        })

        coordinator.begin()
        coordinator.begin()
        coordinator.begin()
        XCTAssertEqual(creations, 1)
        XCTAssertTrue(coordinator.isActive)
    }

    func test_endInvalidatesSession() async throws {
        let stub = StubBackgroundSessionHandle()
        let coordinator = BackgroundSessionCoordinator(factory: { stub })
        coordinator.begin()
        coordinator.end()
        XCTAssertEqual(stub.invalidateCount, 1)
        XCTAssertFalse(coordinator.isActive)
    }

    func test_endIsNoOpWhenInactive() async throws {
        let stub = StubBackgroundSessionHandle()
        let coordinator = BackgroundSessionCoordinator(factory: { stub })
        coordinator.end()
        coordinator.end()
        XCTAssertEqual(stub.invalidateCount, 0)
    }

    func test_canRebeginAfterEnd() async throws {
        var creations = 0
        let coordinator = BackgroundSessionCoordinator(factory: {
            creations += 1
            return StubBackgroundSessionHandle()
        })

        coordinator.begin()
        coordinator.end()
        coordinator.begin()
        XCTAssertEqual(creations, 2)
    }
}

@MainActor
private final class StubBackgroundSessionHandle: BackgroundSessionHandle {
    var startCount = 0
    var invalidateCount = 0

    func start() { startCount += 1 }
    func invalidate() { invalidateCount += 1 }
}
