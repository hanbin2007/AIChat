//
//  SSEParserTests.swift
//  AIChat Watch AppTests
//
//  Covers the pure incremental parser at `Networking/SSEParser.swift`.
//  Asserts behaviour around chunk boundaries, multi-line `data:`,
//  unknown fields, and (importantly) that the legacy `event: delta`
//  synonym still parses as a generic event — the higher-level dispatch
//  in `ChatStreamSession` is the layer that rejects it, not the parser.
//
//  The fixtures use explicit `\n`-terminated string literals rather than
//  Swift's `"""` heredoc form. SSE delimits events with a blank line
//  (i.e. a trailing `\n\n` byte sequence), and Swift heredocs strip the
//  newline immediately preceding the closing `"""`, which silently
//  removes the terminator and prevents events from being emitted.
//

import XCTest
@testable import AIChat_Watch_App

final class SSEParserTests: XCTestCase {

    func test_parsesSingleAnswerDeltaEvent() async throws {
        let parser = SSEParser()
        let raw = "event: answer_delta\n"
            + "data: {\"type\":\"answer_delta\",\"text\":\"hello\"}\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "answer_delta")
        XCTAssertEqual(events.first?.data, #"{"type":"answer_delta","text":"hello"}"#)
    }

    func test_handlesChunkSplitInsideEvent() async throws {
        let parser = SSEParser()
        var events: [SSEEvent] = []
        events += parser.feed(Data("event: answer_delta\n".utf8))
        events += parser.feed(Data(#"data: {"type":"answer_delta","text":"hi"#.utf8))
        events += parser.feed(Data(#""}"#.utf8))
        events += parser.feed(Data("\n\n".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "answer_delta")
    }

    func test_handlesMultilineDataField() async throws {
        let parser = SSEParser()
        let raw = "event: model_content\n"
            + "data: line1\n"
            + "data: line2\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func test_ignoresCommentLines() async throws {
        let parser = SSEParser()
        let raw = ": keepalive\n"
            + "event: done\n"
            + "data: {\"type\":\"done\"}\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "done")
    }

    func test_defaultsEventNameToMessage() async throws {
        let parser = SSEParser()
        let raw = "data: {\"type\":\"answer_delta\",\"text\":\"x\"}\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.first?.event, "message")
    }

    func test_legacyDeltaEventStillParsesAtParserLayer() async throws {
        // The parser has no knowledge of the relay's vocabulary; it must
        // emit the event verbatim. The dispatcher in ChatStreamSession
        // is the layer that rejects `delta`. This guard ensures the
        // synonym keeps the parser honest while still being rejected
        // higher up.
        let parser = SSEParser()
        let raw = "event: delta\n"
            + "data: {\"text\":\"x\"}\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.first?.event, "delta")
    }

    func test_flushReturnsTrailingEventWithoutBlankLine() async throws {
        let parser = SSEParser()
        _ = parser.feed(Data("event: done\ndata: {\"type\":\"done\"}\n".utf8))
        let trailing = parser.flush()
        XCTAssertEqual(trailing?.event, "done")
    }

    func test_handlesMultiByteUTF8AcrossChunks() async throws {
        let parser = SSEParser()
        // "你好" → bytes E4 BD A0 E5 A5 BD; split mid-character.
        let prefix = Data("data: ".utf8) + Data([0xE4, 0xBD])
        let suffix = Data([0xA0, 0xE5, 0xA5, 0xBD]) + Data("\n\n".utf8)
        var events: [SSEEvent] = []
        events += parser.feed(prefix)
        events += parser.feed(suffix)
        // The current implementation parses lines, not raw chars, so a
        // multi-byte sequence split mid-line still produces a single event
        // when the newline arrives. The data is the joined UTF-8 line.
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "你好")
    }

    func test_emitsMultipleEventsInOneChunk() async throws {
        let parser = SSEParser()
        let raw = "event: answer_delta\n"
            + "data: {\"text\":\"a\"}\n"
            + "\n"
            + "event: answer_delta\n"
            + "data: {\"text\":\"b\"}\n"
            + "\n"
            + "event: done\n"
            + "data: {\"type\":\"done\"}\n"
            + "\n"
        let events = parser.feed(Data(raw.utf8))
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.event), ["answer_delta", "answer_delta", "done"])
    }
}
