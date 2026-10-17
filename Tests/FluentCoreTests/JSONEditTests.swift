import XCTest
@testable import FluentCore

final class JSONEditTests: XCTestCase {
    private let config = """
    {
      "baseURL": "https://api.example.com/v1",
      "terminalCellWidth": 9.7,
      "fuzzyPinyin": ["zh=z",
                      "an=ang"],
      "nested": {"a": [1, {"b": "}"}]},
      "note": "a \\"quoted\\" , brace }"
    }

    """

    func testReplacingAValueKeepsEverythingElse() throws {
        let edited = try XCTUnwrap(JSONEdit.setting("terminalCellWidth", to: 8.5, in: config))
        XCTAssertEqual(edited, config.replacingOccurrences(of: "9.7", with: "8.5"))
        let note = try XCTUnwrap(JSONEdit.setting("note", to: "plain", in: config))
        XCTAssertTrue(note.contains("\"note\": \"plain\"\n}"))
        XCTAssertTrue(note.contains("\"nested\": {\"a\": [1, {\"b\": \"}\"}]},"))
    }

    func testAMissingKeyGoesAfterTheLastOneWithTheSameIndent() throws {
        let edited = try XCTUnwrap(JSONEdit.setting("chinese", to: "pinyin", in: config))
        XCTAssertTrue(edited.hasSuffix("brace }\",\n  \"chinese\": \"pinyin\"\n}\n"))
        XCTAssertEqual(JSONEdit.setting("k", to: true, in: "{}"), "{\n  \"k\": true\n}")
        XCTAssertEqual(JSONEdit.setting("k", to: 1, in: #"{"a":0}"#), #"{"a":0, "k": 1}"#)
    }

    func testNilRemovesTheKey() throws {
        let first = try XCTUnwrap(JSONEdit.setting("baseURL", to: nil, in: config))
        XCTAssertTrue(first.hasPrefix("{\n  \"terminalCellWidth\": 9.7,"))
        let middle = try XCTUnwrap(JSONEdit.setting("fuzzyPinyin", to: nil, in: config))
        XCTAssertFalse(middle.contains("zh=z"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(middle.utf8)))
        let last = try XCTUnwrap(JSONEdit.setting("note", to: nil, in: config))
        XCTAssertTrue(last.hasSuffix("}]}\n}\n"))
        XCTAssertEqual(JSONEdit.setting("a", to: nil, in: #"{"a": 1}"#), "{}")
        XCTAssertEqual(JSONEdit.setting("missing", to: nil, in: config), config)
    }

    func testValuesAreWrittenAsTyped() {
        XCTAssertEqual(JSONEdit.encode(9.7), "9.7")
        XCTAssertEqual(JSONEdit.encode(350), "350")
        XCTAssertEqual(JSONEdit.encode(350.0), "350")
        XCTAssertEqual(JSONEdit.encode(true), "true")
        XCTAssertEqual(JSONEdit.encode(NSNumber(value: false)), "false")
        XCTAssertEqual(JSONEdit.encode("a/\"b\""), #""a/\"b\"""#)
        XCTAssertEqual(JSONEdit.encode(["zh=z", "an=ang"]), #"["zh=z", "an=ang"]"#)
        XCTAssertNil(JSONEdit.encode(Double.nan))
    }

    func testNotAnObjectIsLeftAlone() {
        XCTAssertNil(JSONEdit.setting("a", to: 1, in: "[1, 2]"))
        XCTAssertNil(JSONEdit.setting("a", to: 1, in: "{\"a\": "))
    }
}
