//
//  RelaySecureStore.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/15.
//

import Foundation
import Security

struct RelaySecureStore {
    enum Key: String {
        case geminiAPIKey = "gemini_api_key"
        case relayBearerToken = "relay_bearer_token"
    }

    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "hanbin.AIChatRelay") {
        self.service = service
    }

    func string(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return value
    }

    func set(_ value: String, for key: Key) {
        if value.isEmpty {
            removeValue(for: key)
            return
        }

        let encodedValue = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes = [
            kSecValueData as String: encodedValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ] as [String: Any]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        var insertQuery = query
        insertQuery.merge(attributes) { _, new in new }
        SecItemAdd(insertQuery as CFDictionary, nil)
    }

    func removeValue(for key: Key) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
