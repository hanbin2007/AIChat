//
//  RelayClientErrorTests.swift
//  AIChat Watch AppTests
//
//  Asserts the HTTP status → typed `RelayClientError` mapping in
//  `Networking/RelayAPIError.swift`. The relay's uniform
//  `{ "message": String }` envelope is the standard error body; we
//  surface 402 (insufficient credits) and 429 (rate limit) specifically
//  because the rest of the app reacts to them.
//

import XCTest
@testable import AIChat_Watch_App

final class RelayClientErrorTests: XCTestCase {

    func test_400_extractsMessageFromEnvelope() async throws {
        let body = #"{"message":"missing model"}"#.data(using: .utf8)!
        let error = RelayClientError.from(status: 400, body: body, headers: [:])
        guard case let .badRequest(message) = error else {
            return XCTFail("expected badRequest, got \(error)")
        }
        XCTAssertEqual(message, "missing model")
    }

    func test_401_unauthorizedWithoutMessageKeepsNil() async throws {
        let error = RelayClientError.from(status: 401, body: Data(), headers: [:])
        guard case let .unauthorized(message) = error else {
            return XCTFail("expected unauthorized, got \(error)")
        }
        XCTAssertNil(message)
    }

    func test_402_paymentRequiredSurfacesMessage() async throws {
        let body = #"{"message":"insufficient credits"}"#.data(using: .utf8)!
        let error = RelayClientError.from(status: 402, body: body, headers: [:])
        guard case let .paymentRequired(message) = error else {
            return XCTFail("expected paymentRequired, got \(error)")
        }
        XCTAssertEqual(message, "insufficient credits")
    }

    func test_429_parsesRetryAfterFromHeader() async throws {
        let headers: [AnyHashable: Any] = ["Retry-After": "12"]
        let body = #"{"message":"slow down"}"#.data(using: .utf8)!
        let error = RelayClientError.from(status: 429, body: body, headers: headers)
        guard case let .rateLimited(retryAfter, message) = error else {
            return XCTFail("expected rateLimited, got \(error)")
        }
        XCTAssertEqual(retryAfter, 12)
        XCTAssertEqual(message, "slow down")
    }

    func test_429_retryAfterIsNilWhenHeaderMissing() async throws {
        let error = RelayClientError.from(status: 429, body: Data(), headers: [:])
        guard case let .rateLimited(retryAfter, _) = error else {
            return XCTFail("expected rateLimited, got \(error)")
        }
        XCTAssertNil(retryAfter)
    }

    func test_499_clientClosedHasNoMessage() async throws {
        let error = RelayClientError.from(status: 499, body: Data(), headers: [:])
        XCTAssertEqual(error, .clientClosed)
    }

    func test_502_upstreamSurfacesStatusAndMessage() async throws {
        let body = #"{"message":"bad gateway"}"#.data(using: .utf8)!
        let error = RelayClientError.from(status: 502, body: body, headers: [:])
        guard case let .upstream(status, message) = error else {
            return XCTFail("expected upstream, got \(error)")
        }
        XCTAssertEqual(status, 502)
        XCTAssertEqual(message, "bad gateway")
    }

    func test_500_serverGenericFallback() async throws {
        let error = RelayClientError.from(status: 500, body: Data(), headers: [:])
        guard case let .server(status, _) = error else {
            return XCTFail("expected server, got \(error)")
        }
        XCTAssertEqual(status, 500)
    }
}
