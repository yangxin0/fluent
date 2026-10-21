import XCTest
@testable import FluentCore

final class KeyComboTests: XCTestCase {
    func testNamesFromKeyPresses() {
        XCTAssertEqual(KeyCombo.name(ctrl: true, opt: false, shift: false, cmd: false, key: "x"), "ctrl-x")
        XCTAssertEqual(KeyCombo.name(ctrl: true, opt: false, shift: true, cmd: false, key: "B"), "ctrl-shift-b")
        XCTAssertEqual(KeyCombo.name(ctrl: false, opt: true, shift: false, cmd: true, key: "f1"), "opt-cmd-f1")
        XCTAssertEqual(KeyCombo.name(ctrl: true, opt: false, shift: false, cmd: false, key: "-"), "ctrl--")
        // Shift alone is typing, not a shortcut.
        XCTAssertNil(KeyCombo.name(ctrl: false, opt: false, shift: true, cmd: false, key: "x"))
        XCTAssertNil(KeyCombo.name(ctrl: false, opt: false, shift: false, cmd: false, key: "x"))
    }

    func testNamesFromTheConfig() {
        XCTAssertEqual(KeyCombo.normalized("Ctrl-X"), "ctrl-x")
        XCTAssertEqual(KeyCombo.normalized(" control - shift - b "), "ctrl-shift-b")
        XCTAssertEqual(KeyCombo.normalized("shift-ctrl-b"), "ctrl-shift-b")
        XCTAssertEqual(KeyCombo.normalized("command-alt-k"), "opt-cmd-k")
        XCTAssertEqual(KeyCombo.normalized("ctrl--"), "ctrl--")
        XCTAssertNil(KeyCombo.normalized("x"))
        XCTAssertNil(KeyCombo.normalized("shift-x"))
        XCTAssertNil(KeyCombo.normalized("ctrl-shift"))
        XCTAssertNil(KeyCombo.normalized("hyper-x"))
        XCTAssertNil(KeyCombo.normalized(""))
    }

    func testPrefixKeysInTheConfig() throws {
        func decode(_ extra: String) throws -> AppConfig {
            try JSONDecoder().decode(AppConfig.self, from: Data(#"{"baseURL":"u","apiKey":"k","model":"m"\#(extra)}"#.utf8))
        }
        XCTAssertEqual(try decode("").prefixKeys, [])
        XCTAssertEqual(try decode(#","prefixKeys":["Ctrl-X","x",3,"control-b"]"#).prefixKeys, ["ctrl-x", "ctrl-b"])
        XCTAssertEqual(try decode(#","prefixKeys":"ctrl-x""#).prefixKeys, [])
    }
}
