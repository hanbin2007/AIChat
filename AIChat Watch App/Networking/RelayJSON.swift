//
//  RelayJSON.swift
//  AIChat Watch App
//
//  Shared `JSONEncoder` / `JSONDecoder` factories for relay traffic.
//  Date format is ISO-8601 with fractional seconds to match the
//  Next.js relay's `Date.toJSON()` output (e.g. `2026-05-08T12:30:45.123Z`).
//

import Foundation

enum RelayJSON {
    /// Encoder used for every relay request body. Keys are camelCase
    /// (the relay also accepts snake_case but we send canonical
    /// camelCase). Dates are ISO-8601 with fractional seconds.
    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601Formatter.string(from: date))
        }
        return encoder
    }

    /// Decoder used for every relay response body. Tolerates trailing
    /// `Z` and millisecond precision; falls back to `Date(timeIntervalSince1970:)`
    /// for numeric epochs in case the server emits them.
    nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                if let date = iso8601Formatter.date(from: raw) {
                    return date
                }
                if let date = iso8601FormatterWholeSeconds.date(from: raw) {
                    return date
                }
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format from relay"
            )
        }
        return decoder
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterWholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
