//
//  RelayChatDTOTests.swift
//  AIChat Watch AppTests
//
//  Round-trips for the new `RelayStream*` chat DTOs. Asserts canonical
//  camelCase keys on the wire (the relay accepts both casings but the
//  Watch should send canonical camelCase).
//

import XCTest
@testable import AIChat_Watch_App

final class RelayChatDTOTests: XCTestCase {

    func test_streamRequestEncodesCamelCaseKeys() async throws {
        let request = RelayStreamRequest(
            model: "gemini-3-flash-preview",
            systemPrompt: nil,
            systemInstructionParts: nil,
            thinkingIntensity: .balanced,
            maxOutputTokens: 4096,
            includeThoughts: true,
            usesGoogleSearch: false,
            usesCodeExecution: false,
            messages: [
                RelayStreamMessage(
                    role: "user",
                    text: "hi",
                    modelResponseParts: nil,
                    attachments: []
                )
            ]
        )
        let data = try RelayJSON.makeEncoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"thinkingIntensity\""))
        XCTAssertTrue(json.contains("\"maxOutputTokens\""))
        XCTAssertTrue(json.contains("\"includeThoughts\""))
        XCTAssertTrue(json.contains("\"usesGoogleSearch\""))
        XCTAssertTrue(json.contains("\"usesCodeExecution\""))
        XCTAssertFalse(json.contains("max_output_tokens"))
    }

    func test_streamAttachmentEncodesCanonicalKeys() async throws {
        let attachment = RelayStreamAttachment(
            mimeType: "image/png",
            base64Data: "AAAA",
            filename: "x.png"
        )
        let data = try RelayJSON.makeEncoder().encode(attachment)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"mimeType\""))
        XCTAssertTrue(json.contains("\"base64Data\""))
        XCTAssertFalse(json.contains("base64_data"))
    }

    func test_transcribeResponseDecodesEitherTextOrTranscriptKey() async throws {
        let textJSON = #"{"text":"hello"}"#.data(using: .utf8)!
        let viaText = try JSONDecoder().decode(RelayTranscribeResponse.self, from: textJSON)
        XCTAssertEqual(viaText.text, "hello")

        let transcriptJSON = #"{"transcript":"world","model":"x"}"#.data(using: .utf8)!
        let viaTranscript = try JSONDecoder().decode(RelayTranscribeResponse.self, from: transcriptJSON)
        XCTAssertEqual(viaTranscript.text, "world")
        XCTAssertEqual(viaTranscript.model, "x")
    }

    func test_streamFrameDecodesAllEventTypes() async throws {
        let cases: [String] = [
            #"{"type":"answer_delta","text":"a"}"#,
            #"{"type":"thought_delta","text":"t"}"#,
            #"{"type":"model_content","parts":[]}"#,
            #"{"type":"attachment","attachment":{"mimeType":"image/png","base64Data":"AAA","filename":"x.png"}}"#,
            #"{"type":"error","message":"boom"}"#,
            #"{"type":"done","finishReason":"STOP"}"#
        ]
        let decoder = JSONDecoder()
        for raw in cases {
            let data = raw.data(using: .utf8)!
            XCTAssertNoThrow(try decoder.decode(RelayStreamFrame.self, from: data))
        }
    }
}
