//
//  RelayDebugFormatter.swift
//  AIChat Relay
//
//  Created by Codex on 2026/3/9.
//

import Foundation

enum RelayDebugFormatter {
    static func httpRequest(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?
    ) -> String {
        var sections = [
            "Method:\n\(method)",
            "URL:\n\(url)",
            "Headers:\n\(formattedHeaders(headers))",
            "Body:\n\(formattedBody(body))"
        ]

        return sections.joined(separator: "\n\n")
    }

    static func httpResponse(
        statusCode: Int,
        headers: [String: String],
        body: Data?
    ) -> String {
        [
            "Status:\n\(statusCode)",
            "Headers:\n\(formattedHeaders(headers))",
            "Body:\n\(formattedBody(body))"
        ]
        .joined(separator: "\n\n")
    }

    static func prettyJSON(_ object: Any) -> String {
        let sanitizedObject = sanitize(object, key: nil)
        guard JSONSerialization.isValidJSONObject(sanitizedObject),
              let data = try? JSONSerialization.data(withJSONObject: sanitizedObject, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: sanitizedObject)
        }

        return string
    }

    private static func formattedHeaders(_ headers: [String: String]) -> String {
        guard headers.isEmpty == false else {
            return "<empty>"
        }

        return headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { key, value in
                let lowercasedKey = key.lowercased()
                return "\(key): \(redactedStringIfNeeded(value, key: lowercasedKey))"
            }
            .joined(separator: "\n")
    }

    private static func formattedBody(_ body: Data?) -> String {
        guard let body, body.isEmpty == false else {
            return "<empty>"
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: body) {
            return prettyJSON(jsonObject)
        }

        if let string = String(data: body, encoding: .utf8) {
            return truncated(string)
        }

        return "<\(body.count) bytes binary>"
    }

    private static func sanitize(_ value: Any, key: String?) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { partialResult, pair in
                partialResult[pair.key] = sanitize(pair.value, key: pair.key)
            }
        }

        if let array = value as? [Any] {
            return array.map { sanitize($0, key: key) }
        }

        if let string = value as? String {
            return redactedStringIfNeeded(string, key: key)
        }

        return value
    }

    private static func redactedStringIfNeeded(_ value: String, key: String?) -> String {
        let normalizedKey = key?.lowercased() ?? ""

        if [
            "authorization",
            "x-goog-api-key",
            "relaybearertoken",
            "relaybearer_token",
            "bearer_token",
            "token"
        ].contains(normalizedKey) {
            return "<redacted>"
        }

        if normalizedKey == "data" || normalizedKey == "base64data" || normalizedKey == "base64_data" {
            return "<redacted base64: \(value.count) chars>"
        }

        return truncated(value)
    }

    private static func truncated(_ value: String, head: Int = 300, tail: Int = 80) -> String {
        guard value.count > head + tail else {
            return value
        }

        let prefix = String(value.prefix(head))
        let suffix = String(value.suffix(tail))
        return "\(prefix)\n... <truncated \(value.count - head - tail) chars> ...\n\(suffix)"
    }
}
