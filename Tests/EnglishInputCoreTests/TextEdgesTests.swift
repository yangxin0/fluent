import XCTest
@testable import EnglishInputCore

final class TextEdgesTests: XCTestCase {
    func testLeadingSpaceIsRestored() {
        XCTAssertEqual(TextEdges.restoringEdges(of: " next sentance", to: "Next sentence."),
                       " Next sentence.")
    }

    func testTrailingWhitespaceIsRestored() {
        XCTAssertEqual(TextEdges.restoringEdges(of: "helo wrld ", to: "Hello world"),
                       "Hello world ")
        XCTAssertEqual(TextEdges.restoringEdges(of: "  helo\n", to: " Hello. "),
                       "  Hello.\n")
    }

    func testNoEdgesMeansNoChange() {
        XCTAssertEqual(TextEdges.restoringEdges(of: "helo", to: "Hello"), "Hello")
    }

    func testBlankImprovementIsLeftAlone() {
        XCTAssertEqual(TextEdges.restoringEdges(of: " x ", to: "   "), "   ")
        XCTAssertEqual(TextEdges.restoringEdges(of: " x ", to: ""), "")
    }

    func testAllWhitespaceRawIsLeftAlone() {
        XCTAssertEqual(TextEdges.restoringEdges(of: "   ", to: "Hello"), "Hello")
    }
}
