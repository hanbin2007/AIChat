//
//  OfflineActivationTests.swift
//  AIChat Watch AppTests
//
//  Created by Codex on 2026/3/8.
//

import XCTest
@testable import AIChat_Watch_App

final class OfflineActivationTests: XCTestCase {
    func testRequestCodeRoundTripsDeviceAndTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_762_400_000)
        let deviceToken = OfflineActivation.deviceToken(for: "WATCH-DEVICE-001")

        let requestCode = OfflineActivation.makeRequestCode(deviceToken: deviceToken, now: now)
        let decoded = try OfflineActivation.decodeRequestCode(requestCode)

        XCTAssertEqual(decoded.deviceToken, deviceToken)
        XCTAssertEqual(decoded.issuedAt, now)
    }

    func testActivationCodeCarriesPolicyFields() throws {
        let now = Date(timeIntervalSince1970: 1_762_400_000)
        let deviceToken = OfflineActivation.deviceToken(for: "WATCH-DEVICE-002")
        let requestCode = OfflineActivation.makeRequestCode(deviceToken: deviceToken, now: now)
        let validUntil = now.addingTimeInterval(7 * 24 * 60 * 60)
        let policy = OfflineActivationPolicy(
            validFrom: now,
            validUntil: validUntil,
            messageLimit: 25,
            allowedModelIDs: ["gemini-3.1-pro-preview", "gemini-2.5-flash"]
        )

        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: requestCode,
            policy: policy
        )
        let license = try OfflineActivation.decodeActivationCode(activationCode)

        XCTAssertEqual(license.deviceToken, deviceToken)
        XCTAssertEqual(license.requestIssuedAt, now)
        XCTAssertEqual(license.validFrom, now)
        XCTAssertEqual(license.validUntil, validUntil)
        XCTAssertEqual(license.messageLimit, 25)
        XCTAssertEqual(license.allowedModelIDs, Set(["gemini-3.1-pro-preview", "gemini-2.5-flash"]))
    }

    func testActivationRejectsExpiredRequestWindow() throws {
        let now = Date(timeIntervalSince1970: 1_762_400_000)
        let deviceToken = OfflineActivation.deviceToken(for: "WATCH-DEVICE-003")
        let requestCode = OfflineActivation.makeRequestCode(deviceToken: deviceToken, now: now)
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: requestCode,
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: nil,
                allowedModelIDs: nil
            )
        )

        XCTAssertThrowsError(
            try OfflineActivation.activate(
                code: activationCode,
                deviceToken: deviceToken,
                now: now.addingTimeInterval(31 * 60),
                currentState: nil
            )
        ) { error in
            XCTAssertEqual(error as? OfflineActivationError, .requestExpired)
        }
    }

    func testConsumeMessageHonorsMessageLimit() throws {
        let now = Date(timeIntervalSince1970: 1_762_400_000)
        let deviceToken = OfflineActivation.deviceToken(for: "WATCH-DEVICE-004")
        let requestCode = OfflineActivation.makeRequestCode(deviceToken: deviceToken, now: now)
        let activationCode = try OfflineActivation.makeActivationCode(
            requestCode: requestCode,
            policy: OfflineActivationPolicy(
                validFrom: now,
                validUntil: nil,
                messageLimit: 2,
                allowedModelIDs: ["gemini-3-flash-preview"]
            )
        )
        let initialState = try OfflineActivation.activate(
            code: activationCode,
            deviceToken: deviceToken,
            now: now,
            currentState: nil
        )

        let firstState = try OfflineActivation.consumeMessage(
            from: initialState,
            deviceToken: deviceToken,
            modelID: "gemini-3-flash-preview",
            now: now
        )
        let secondState = try OfflineActivation.consumeMessage(
            from: firstState,
            deviceToken: deviceToken,
            modelID: "gemini-3-flash-preview",
            now: now
        )

        XCTAssertEqual(secondState.usedMessageCount, 2)
        XCTAssertEqual(secondState.remainingMessageCount, 0)

        XCTAssertThrowsError(
            try OfflineActivation.consumeMessage(
                from: secondState,
                deviceToken: deviceToken,
                modelID: "gemini-3-flash-preview",
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? OfflineActivationError, .messageLimitReached)
        }
    }
}
