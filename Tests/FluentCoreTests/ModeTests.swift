import XCTest
@testable import FluentCore

final class ModeTests: XCTestCase {
    func testAllModesHaveInstructionsWithOutputRule() {
        for mode in Mode.allCases {
            XCTAssertFalse(mode.instructions.isEmpty)
            XCTAssertTrue(mode.instructions.contains("Output ONLY the resulting text"),
                          "\(mode) missing output rule")
        }
    }

    func testNextCycles() {
        XCTAssertEqual(Mode.fix.next, .polish)
        XCTAssertEqual(Mode.polish.next, .interpret)
        XCTAssertEqual(Mode.interpret.next, .fix)
    }
}
