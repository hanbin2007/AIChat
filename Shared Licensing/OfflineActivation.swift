//
//  OfflineActivation.swift
//  AIChat
//
//  Created by Codex on 2026/3/8.
//

import CryptoKit
import Foundation

nonisolated enum OfflineActivation {
    static let requestWindow: TimeInterval = 30 * 60
    static let requestVersion: UInt8 = 1
    static let licenseVersion: UInt8 = 1
    static let licenseTagLength = 10

    // Replace this seed before shipping. The same seed must remain in the
    // watch verifier and the offline key generator.
    private static let sharedSecretSeed = "AIChat-Offline-Activation-2026-Replace-Me"

    private static var signingKey: SymmetricKey {
        let digest = SHA256.hash(data: Data(sharedSecretSeed.utf8))
        return SymmetricKey(data: Data(digest))
    }

    static func deviceToken(for rawIdentifier: String) -> UInt64 {
        let normalized = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let digest = SHA256.hash(data: Data("AIChat-Watch-\(normalized)".utf8))
        return Array(digest.prefix(8)).reduce(into: UInt64.zero) { partialResult, byte in
            partialResult = (partialResult << 8) | UInt64(byte)
        }
    }

    static func displayToken(for deviceToken: UInt64) -> String {
        String(deviceToken, radix: 16, uppercase: true)
            .leftPadding(toLength: 16, withPad: "0")
            .chunked(every: 4)
            .joined(separator: "-")
    }

    static func makeRequestCode(deviceToken: UInt64, now: Date = .now) -> String {
        var writer = ActivationBinaryWriter()
        writer.append(requestVersion)
        writer.append(deviceToken)
        writer.append(timestamp(from: now))

        let checksum = crc16(writer.data)
        writer.append(checksum)

        return format(CrockfordBase32.encode(writer.data), groupSize: 4)
    }

    static func decodeRequestCode(_ rawCode: String) throws -> OfflineActivationRequest {
        let normalized = normalize(rawCode)
        let data = try CrockfordBase32.decode(normalized)
        var reader = ActivationBinaryReader(data: data)

        let version = try reader.readUInt8()
        guard version == requestVersion else {
            throw OfflineActivationError.unsupportedVersion
        }

        let deviceToken = try reader.readUInt64()
        let issuedAtTimestamp = try reader.readUInt32()
        let checksum = try reader.readUInt16()

        guard reader.isAtEnd else {
            throw OfflineActivationError.invalidRequest
        }

        var checksumWriter = ActivationBinaryWriter()
        checksumWriter.append(version)
        checksumWriter.append(deviceToken)
        checksumWriter.append(issuedAtTimestamp)

        guard crc16(checksumWriter.data) == checksum else {
            throw OfflineActivationError.invalidRequest
        }

        return OfflineActivationRequest(
            deviceToken: deviceToken,
            issuedAt: date(from: issuedAtTimestamp)
        )
    }

    static func makeActivationCode(
        requestCode: String,
        policy: OfflineActivationPolicy
    ) throws -> String {
        let request = try decodeRequestCode(requestCode)
        let payload = try encodeLicensePayload(
            deviceToken: request.deviceToken,
            requestIssuedAt: request.issuedAt,
            policy: policy
        )
        let tag = authenticationTag(for: payload)
        return format(CrockfordBase32.encode(payload + tag), groupSize: 5)
    }

    static func decodeActivationCode(_ rawCode: String) throws -> OfflineActivationLicense {
        let normalized = normalize(rawCode)
        let data = try CrockfordBase32.decode(normalized)

        guard data.count == 35 else {
            throw OfflineActivationError.invalidActivationCode
        }

        let payload = Data(data.prefix(25))
        let actualTag = Data(data.suffix(licenseTagLength))
        let expectedTag = authenticationTag(for: payload)
        guard actualTag == expectedTag else {
            throw OfflineActivationError.invalidSignature
        }

        var reader = ActivationBinaryReader(data: payload)
        let version = try reader.readUInt8()
        guard version == licenseVersion else {
            throw OfflineActivationError.unsupportedVersion
        }

        let deviceToken = try reader.readUInt64()
        let requestIssuedAt = date(from: try reader.readUInt32())
        let validFrom = date(from: try reader.readUInt32())
        let rawValidUntil = try reader.readUInt32()
        let rawMessageLimit = try reader.readUInt16()
        let modelMask = try reader.readUInt16()

        guard reader.isAtEnd else {
            throw OfflineActivationError.invalidActivationCode
        }

        let validUntil = rawValidUntil == 0 ? nil : date(from: rawValidUntil)
        let messageLimit = rawMessageLimit == 0 ? nil : Int(rawMessageLimit)

        guard validUntil == nil || validUntil! >= validFrom else {
            throw OfflineActivationError.invalidActivationCode
        }

        return OfflineActivationLicense(
            deviceToken: deviceToken,
            requestIssuedAt: requestIssuedAt,
            validFrom: validFrom,
            validUntil: validUntil,
            messageLimit: messageLimit,
            modelMask: modelMask
        )
    }

    static func activate(
        code rawCode: String,
        deviceToken: UInt64,
        now: Date = .now,
        currentState: OfflineActivationState?
    ) throws -> OfflineActivationState {
        let license = try decodeActivationCode(rawCode)
        try validateForActivation(license: license, deviceToken: deviceToken, now: now)

        let fingerprint = Data(SHA256.hash(data: Data(normalize(rawCode).utf8))).hexString
        let preservedUsage = currentState?.activationCodeFingerprint == fingerprint ? currentState?.usedMessageCount ?? 0 : 0

        return OfflineActivationState(
            license: license,
            activationCodeFingerprint: fingerprint,
            activatedAt: now,
            usedMessageCount: preservedUsage
        )
    }

    static func validateForActivation(
        license: OfflineActivationLicense,
        deviceToken: UInt64,
        now: Date = .now
    ) throws {
        guard license.deviceToken == deviceToken else {
            throw OfflineActivationError.deviceMismatch
        }

        let elapsed = now.timeIntervalSince(license.requestIssuedAt)
        guard elapsed >= -120 else {
            throw OfflineActivationError.requestFromFuture
        }

        guard elapsed <= requestWindow else {
            throw OfflineActivationError.requestExpired
        }
    }

    static func status(
        for state: OfflineActivationState?,
        deviceToken: UInt64,
        now: Date = .now
    ) -> OfflineActivationStatus {
        guard let state else {
            return .inactive
        }

        guard state.license.deviceToken == deviceToken else {
            return .invalid("当前授权不属于这块 Apple Watch。")
        }

        if now < state.license.validFrom {
            return .pending(state)
        }

        if let validUntil = state.license.validUntil, now > validUntil {
            return .expired(state)
        }

        if let remaining = state.remainingMessageCount, remaining <= 0 {
            return .exhausted(state)
        }

        return .active(state, remainingMessages: state.remainingMessageCount)
    }

    static func consumeMessage(
        from state: OfflineActivationState?,
        deviceToken: UInt64,
        modelID: String,
        now: Date = .now
    ) throws -> OfflineActivationState {
        guard let state else {
            throw OfflineActivationError.notActivated
        }

        switch status(for: state, deviceToken: deviceToken, now: now) {
        case .inactive:
            throw OfflineActivationError.notActivated
        case .pending:
            throw OfflineActivationError.notYetActive(startDate: state.license.validFrom)
        case .expired:
            throw OfflineActivationError.licenseExpired
        case .exhausted:
            throw OfflineActivationError.messageLimitReached
        case .invalid(let message):
            throw OfflineActivationError.custom(message)
        case .active:
            break
        }

        guard state.license.allows(modelID: modelID) else {
            throw OfflineActivationError.modelNotAllowed
        }

        guard let messageLimit = state.license.messageLimit else {
            return state
        }

        let nextUsage = state.usedMessageCount + 1
        guard nextUsage <= messageLimit else {
            throw OfflineActivationError.messageLimitReached
        }

        var updatedState = state
        updatedState.usedMessageCount = nextUsage
        return updatedState
    }

    static func recommendedModel(
        preferredModelID: String,
        defaultModelID: String,
        state: OfflineActivationState?,
        deviceToken: UInt64,
        now: Date = .now
    ) -> String {
        guard case .active(let state, _) = status(for: state, deviceToken: deviceToken, now: now) else {
            return preferredModelID
        }

        if state.license.allows(modelID: preferredModelID) {
            return preferredModelID
        }

        if state.license.allows(modelID: defaultModelID) {
            return defaultModelID
        }

        return LicensedModelCatalog.firstAllowedModelID(
            preferredOrder: [preferredModelID, defaultModelID] + LicensedModelCatalog.supportedModels.map(\.id),
            mask: state.license.modelMask
        ) ?? preferredModelID
    }

    static func allowedModelIDs(
        for state: OfflineActivationState?,
        deviceToken: UInt64,
        now: Date = .now
    ) -> Set<String>? {
        switch status(for: state, deviceToken: deviceToken, now: now) {
        case .pending(let state), .active(let state, _), .expired(let state), .exhausted(let state):
            return state.license.allowedModelIDs
        case .inactive, .invalid:
            return nil
        }
    }

    static func normalize(_ rawCode: String) -> String {
        rawCode
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
            .map { character in
                switch character {
                case "O":
                    return "0"
                case "I", "L":
                    return "1"
                default:
                    return character
                }
            }
            .reduce(into: String()) { partialResult, character in
                partialResult.append(character)
            }
    }

    static func formatForDisplay(_ rawCode: String, groupSize: Int = 5) -> String {
        format(normalize(rawCode), groupSize: groupSize)
    }

    private static func encodeLicensePayload(
        deviceToken: UInt64,
        requestIssuedAt: Date,
        policy: OfflineActivationPolicy
    ) throws -> Data {
        if let validUntil = policy.validUntil, validUntil < policy.validFrom {
            throw OfflineActivationError.invalidActivationCode
        }

        if let messageLimit = policy.messageLimit, messageLimit <= 0 || messageLimit > Int(UInt16.max) {
            throw OfflineActivationError.invalidMessageLimit
        }

        var writer = ActivationBinaryWriter()
        writer.append(licenseVersion)
        writer.append(deviceToken)
        writer.append(timestamp(from: requestIssuedAt))
        writer.append(timestamp(from: policy.validFrom))
        writer.append(timestamp(from: policy.validUntil))
        writer.append(UInt16(policy.messageLimit ?? 0))
        writer.append(LicensedModelCatalog.mask(for: policy.allowedModelIDs))
        return writer.data
    }

    private static func authenticationTag(for payload: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: signingKey)
        return Data(mac.prefix(licenseTagLength))
    }

    private static func timestamp(from date: Date?) -> UInt32 {
        guard let date else {
            return 0
        }

        return UInt32(max(0, Int(date.timeIntervalSince1970.rounded(.down))))
    }

    private static func date(from timestamp: UInt32) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func format(_ code: String, groupSize: Int) -> String {
        code.chunked(every: groupSize).joined(separator: "-")
    }

    private static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF

        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }

        return crc
    }
}

nonisolated struct OfflineActivationRequest: Equatable, Hashable, Sendable {
    let deviceToken: UInt64
    let issuedAt: Date

    var displayDeviceToken: String {
        OfflineActivation.displayToken(for: deviceToken)
    }
}

nonisolated struct OfflineActivationPolicy: Equatable, Hashable, Sendable {
    var validFrom: Date
    var validUntil: Date?
    var messageLimit: Int?
    var allowedModelIDs: Set<String>?
}

nonisolated struct OfflineActivationLicense: Codable, Equatable, Hashable, Sendable {
    let deviceToken: UInt64
    let requestIssuedAt: Date
    let validFrom: Date
    let validUntil: Date?
    let messageLimit: Int?
    let modelMask: UInt16

    var allowedModelIDs: Set<String>? {
        LicensedModelCatalog.modelIDs(for: modelMask)
    }

    func allows(modelID: String) -> Bool {
        LicensedModelCatalog.isAllowed(modelID: modelID, mask: modelMask)
    }
}

nonisolated struct OfflineActivationState: Codable, Equatable, Hashable, Sendable {
    let license: OfflineActivationLicense
    let activationCodeFingerprint: String
    let activatedAt: Date
    var usedMessageCount: Int

    var remainingMessageCount: Int? {
        guard let messageLimit = license.messageLimit else {
            return nil
        }

        return max(0, messageLimit - usedMessageCount)
    }
}

nonisolated enum OfflineActivationStatus: Equatable, Sendable {
    case inactive
    case pending(OfflineActivationState)
    case active(OfflineActivationState, remainingMessages: Int?)
    case expired(OfflineActivationState)
    case exhausted(OfflineActivationState)
    case invalid(String)
}

nonisolated enum OfflineActivationError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case invalidActivationCode
    case invalidSignature
    case unsupportedVersion
    case deviceMismatch
    case requestExpired
    case requestFromFuture
    case licenseExpired
    case messageLimitReached
    case modelNotAllowed
    case notActivated
    case notYetActive(startDate: Date)
    case invalidMessageLimit
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "请求码无效，请在手表上重新生成。"
        case .invalidActivationCode:
            return "激活码格式不正确。"
        case .invalidSignature:
            return "激活码校验失败。"
        case .unsupportedVersion:
            return "激活码版本不受支持。"
        case .deviceMismatch:
            return "这个激活码不属于当前 Apple Watch。"
        case .requestExpired:
            return "请求码已超过 30 分钟，请在手表上刷新后重新生成。"
        case .requestFromFuture:
            return "请求时间异常，请检查手表系统时间。"
        case .licenseExpired:
            return "当前授权已过期。"
        case .messageLimitReached:
            return "当前授权的可发送次数已用完。"
        case .modelNotAllowed:
            return "当前授权不允许使用这个模型。"
        case .notActivated:
            return "请先在 Apple Watch 上完成激活。"
        case .notYetActive(let startDate):
            return "授权将在 \(startDate.formatted(date: .abbreviated, time: .shortened)) 生效。"
        case .invalidMessageLimit:
            return "消息次数限制超出可编码范围。"
        case .custom(let message):
            return message
        }
    }
}

private nonisolated struct ActivationBinaryWriter {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func append(_ value: UInt16) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: UInt32) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: UInt64) {
        var value = value.bigEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}

private nonisolated struct ActivationBinaryReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readUInt8() throws -> UInt8 {
        let data = try read(count: 1)
        return data[data.startIndex]
    }

    mutating func readUInt16() throws -> UInt16 {
        let data = try read(count: 2)
        return data.reduce(into: UInt16.zero) { partialResult, byte in
            partialResult = (partialResult << 8) | UInt16(byte)
        }
    }

    mutating func readUInt32() throws -> UInt32 {
        let data = try read(count: 4)
        return data.reduce(into: UInt32.zero) { partialResult, byte in
            partialResult = (partialResult << 8) | UInt32(byte)
        }
    }

    mutating func readUInt64() throws -> UInt64 {
        let data = try read(count: 8)
        return data.reduce(into: UInt64.zero) { partialResult, byte in
            partialResult = (partialResult << 8) | UInt64(byte)
        }
    }

    private mutating func read(count: Int) throws -> Data {
        guard data.count - offset >= count else {
            throw OfflineActivationError.invalidActivationCode
        }

        let slice = data[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }
}

private nonisolated enum CrockfordBase32 {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let values: [Character: UInt8] = {
        var values: [Character: UInt8] = [:]
        for (index, character) in alphabet.enumerated() {
            values[character] = UInt8(index)
        }
        return values
    }()

    static func encode(_ data: Data) -> String {
        guard data.isEmpty == false else {
            return ""
        }

        var buffer = 0
        var bitsLeft = 0
        var output = ""

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8

            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1F
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }

        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1F
            output.append(alphabet[index])
        }

        return output
    }

    static func decode(_ string: String) throws -> Data {
        guard string.isEmpty == false else {
            throw OfflineActivationError.invalidActivationCode
        }

        var buffer = 0
        var bitsLeft = 0
        var output = Data()

        for character in string {
            guard let value = values[character] else {
                throw OfflineActivationError.invalidActivationCode
            }

            buffer = (buffer << 5) | Int(value)
            bitsLeft += 5

            while bitsLeft >= 8 {
                let byte = UInt8((buffer >> (bitsLeft - 8)) & 0xFF)
                output.append(byte)
                bitsLeft -= 8
            }
        }

        return output
    }
}

private nonisolated extension String {
    func leftPadding(toLength length: Int, withPad character: Character) -> String {
        guard count < length else {
            return self
        }

        return String(repeating: String(character), count: length - count) + self
    }

    func chunked(every size: Int) -> [String] {
        guard size > 0 else {
            return [self]
        }

        var result: [String] = []
        var index = startIndex

        while index < endIndex {
            let nextIndex = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<nextIndex]))
            index = nextIndex
        }

        return result
    }
}

private nonisolated extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
