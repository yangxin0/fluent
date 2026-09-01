import XCTest
@testable import EnglishInputCore

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

    func testOutputTextDoneEndsStream() {
        let events = parse([
            "event: response.output_text.done",
            #"data: {"type":"response.output_text.done","text":"Hello there"}"#,
            "",
        ])
        XCTAssertEqual(ResponsesEventInterpreter.interpret(events[0]), .done)
    }
}
