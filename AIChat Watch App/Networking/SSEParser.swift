//
//  SSEParser.swift
//  AIChat Watch App
//
//  Pure incremental parser for `text/event-stream` frames. Has no
//  knowledge of URLSession or the relay's payload schema — `feed(_:)`
//  appends a chunk of bytes and emits any complete `(event, data)`
//  events that became fully available.
//
//  Only the protocol-level event names from the Next.js relay are
//  recognised by callers (`answer_delta`, `thought_delta`,
//  `model_content`, `attachment`, `error`, `done`). The legacy
//  `event: delta` synonym used by the old macOS SwiftUI relay is no
//  longer accepted; it is parsed here as a generic event but the
//  higher-level dispatcher rejects it.
//

import Foundation

struct SSEEvent: Equatable, Sendable {
    /// The `event:` field, defaulted to "message" per the SSE spec.
    let event: String
    /// The concatenated `data:` lines belonging to this event.
    let data: String
}

final class SSEParser {
    private var buffer = Data()
    private var currentEvent: String? = nil
    private var currentData: [String] = []

    init() {}

    /// Append raw bytes from the network and return any events that
    /// became fully formed. May return zero, one, or many events per
    /// call. Does not buffer events across instances.
    func feed(_ chunk: Data) -> [SSEEvent] {
        buffer.append(chunk)
        var events: [SSEEvent] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var lineData = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            if lineData.last == 0x0D {
                lineData.removeLast()
            }
            let line = String(data: lineData, encoding: .utf8) ?? ""
            if let event = consume(line: line) {
                events.append(event)
            }
        }

        return events
    }

    /// Flush any in-progress event when the stream ends without a
    /// trailing blank line. Returns at most one event.
    func flush() -> SSEEvent? {
        guard buffer.isEmpty == false || currentEvent != nil || currentData.isEmpty == false else {
            return nil
        }
        if buffer.isEmpty == false {
            let line = String(data: buffer, encoding: .utf8) ?? ""
            buffer.removeAll(keepingCapacity: false)
            if let event = consume(line: line) {
                return event
            }
        }
        return finishEvent()
    }

    private func consume(line: String) -> SSEEvent? {
        if line.isEmpty {
            return finishEvent()
        }

        // Comments per spec start with ":". Ignore.
        if line.hasPrefix(":") {
            return nil
        }

        if let colon = line.firstIndex(of: ":") {
            let field = String(line[..<colon])
            var valueStart = line.index(after: colon)
            // Per the SSE spec, a single leading space after the colon is stripped.
            if valueStart < line.endIndex, line[valueStart] == " " {
                valueStart = line.index(after: valueStart)
            }
            let value = String(line[valueStart...])
            apply(field: field, value: value)
        } else {
            apply(field: line, value: "")
        }
        return nil
    }

    private func apply(field: String, value: String) {
        switch field {
        case "event":
            currentEvent = value
        case "data":
            currentData.append(value)
        case "id", "retry":
            // Not used by the relay; ignore.
            break
        default:
            break
        }
    }

    private func finishEvent() -> SSEEvent? {
        defer {
            currentEvent = nil
            currentData.removeAll(keepingCapacity: false)
        }
        guard currentData.isEmpty == false else {
            // Lone "event:" line with no data is dropped per spec.
            return nil
        }
        let event = currentEvent?.nonEmptyTrimmed ?? "message"
        let data = currentData.joined(separator: "\n")
        return SSEEvent(event: event, data: data)
    }
}
