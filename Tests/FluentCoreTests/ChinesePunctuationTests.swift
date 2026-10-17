import XCTest
@testable import FluentCore

final class ChinesePunctuationTests: XCTestCase {
    func testCommonPunctuation() {
        var punctuation = ChinesePunctuation()
        XCTAssertEqual(punctuation.convert(","), "，")
        XCTAssertEqual(punctuation.convert("."), "。")
        XCTAssertEqual(punctuation.convert("\\"), "、")
        XCTAssertEqual(punctuation.convert("<"), "《")
    }

    func testPunctuationAndSymbolsGoStraightIn() {
        for key: Character in [".", ",", "(", "-", "\"", "'", "@", "#", "$", "+", "<", "~", "/", "_", "`"] {
            XCTAssertTrue(ChinesePunctuation.isPunctuation(key), "\(key)")
        }
        for key: Character in ["a", "Z", "1", " ", "中"] {
            XCTAssertFalse(ChinesePunctuation.isPunctuation(key), "\(key)")
        }
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
