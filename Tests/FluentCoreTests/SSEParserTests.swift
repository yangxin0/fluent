import XCTest
@testable import FluentCore

final class SSEParserTests: XCTestCase {
    private func parse(_ lines: [String]) -> [SSEEvent] {
        var parser = SSEParser()
        return lines.compactMap { parser.feed(line: $0) }
    }

    func testDeltaEvent() {
        let events = parse([
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"Hello"}"#,
            "",
        ])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .delta("Hello"))
    }

    func testMultipleEventsAndIgnoredLifecycle() {
        let events = parse([
            "event: response.created",
            #"data: {"type":"response.created"}"#,
            "",
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"Hi "}"#,
            "",
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"there"}"#,
            "",
            "event: response.completed",
            #"data: {"type":"response.completed"}"#,
            "",
        ])
        let items = events.map(ResponsesEventInterpreter.interpret)
        XCTAssertEqual(items, [.ignore, .delta("Hi "), .delta("there"), .done])
    }

    func testDataOnlyProviderWithoutEventNames() {
        let events = parse([
            #"data: {"type":"response.output_text.delta","delta":"x"}"#,
            "",
            "data: [DONE]",
            "",
        ])
        let items = events.map(ResponsesEventInterpreter.interpret)
        XCTAssertEqual(items, [.delta("x"), .done])
    }

    func testErrorEvent() {
        let events = parse([
            "event: error",
            #"data: {"type":"error","error":{"message":"rate limited"}}"#,
            "",
        ])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .error("rate limited"))
    }

    func testResponseFailedWithNestedError() {
        let events = parse([
            #"data: {"type":"response.failed","response":{"error":{"message":"bad model"}}}"#,
            "",
        ])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .error("bad model"))
    }

    func testMultilineDataJoined() {
        let events = parse(["data: a", "data: b", ""])
        XCTAssertEqual(events, [SSEEvent(event: nil, data: "a\nb")])
    }

    func testCommentsAndBlankLinesIgnored() {
        XCTAssertTrue(parse([": keepalive", "", ""]).isEmpty)
    }

    func testOutputTextDoneCarriesFinalText() {
        let events = parse([
            "event: response.output_text.done",
            #"data: {"type":"response.output_text.done","text":"Hello there"}"#,
            "",
        ])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .completed("Hello there"))
    }

    func testOutputTextDoneWithoutTextIsEmptyCompletion() {
        let events = parse([#"data: {"type":"response.output_text.done"}"#, ""])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .completed(""))
    }

    private func decode(_ stream: String) throws -> (text: String, finished: Bool) {
        var decoder = ResponsesStreamDecoder()
        var text = ""
        for byte in stream.utf8 {
            text += try decoder.feed(byte) ?? ""
        }
        return (text, decoder.isFinished)
    }

    func testStreamLinesMayEndInCRLFOrABareCR() throws {
        let delta = #"data: {"type":"response.output_text.delta","delta":"Hi"}"#
        let done = #"data: {"type":"response.completed"}"#
        for end in ["\n", "\r\n", "\r"] {
            let result = try decode([delta, "", done, "", ""].joined(separator: end))
            XCTAssertEqual(result.text, "Hi", "line end \(end.debugDescription)")
            XCTAssertTrue(result.finished)
        }
    }

    func testAStreamWithoutATerminalEventIsUnfinished() throws {
        let cut = try decode(#"data: {"type":"response.output_text.delta","delta":"Hello wor"}"# + "\n\n")
        XCTAssertEqual(cut.text, "Hello wor")
        XCTAssertFalse(cut.finished)  // the client then reports "reply cut off"
        XCTAssertTrue(try decode("data: [DONE]\n\n").finished)
    }

    func testIncompleteReplyIsAnError() {
        let events = parse([
            #"data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#,
            "",
        ])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .error("reply incomplete: max_output_tokens"))
    }

    func testErrorBodiesShowTheirMessage() {
        XCTAssertEqual(ResponsesClient.errorMessage(fromBody: #"{  "error": {    "message": "Invalid API key",    "type": "auth"  }}"#),
                       "Invalid API key")
        XCTAssertEqual(ResponsesClient.errorMessage(fromBody: "Bad Gateway"), "Bad Gateway")
    }
}
