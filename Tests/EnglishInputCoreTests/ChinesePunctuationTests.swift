import XCTest
@testable import EnglishInputCore

final class ChinesePunctuationTests: XCTestCase {
    func testCommonPunctuation() {
        var punctuation = ChinesePunctuation()
        XCTAssertEqual(punctuation.convert(","), "，")
        XCTAssertEqual(punctuation.convert("."), "。")
        XCTAssertEqual(punctuation.convert("\\"), "、")
        XCTAssertEqual(punctuation.convert("<"), "《")
    }

    func testQuotesAlternate() {
        var punctuation = ChinesePunctuation()
        XCTAssertEqual(punctuation.convert("\""), "“")
        XCTAssertEqual(punctuation.convert("'"), "‘")
        XCTAssertEqual(punctuation.convert("'"), "’")
        XCTAssertEqual(punctuation.convert("\""), "”")
    }

    func testPagingKeysAndOthersAreLeftAlone() {
        var punctuation = ChinesePunctuation()
        XCTAssertNil(punctuation.convert("-"))
        XCTAssertNil(punctuation.convert("="))
        XCTAssertNil(punctuation.convert("@"))
        XCTAssertNil(punctuation.convert("a"))
    }
}
