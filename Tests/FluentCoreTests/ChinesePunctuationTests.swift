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

    func testPunctuationSymbolsSpacesAndDigitsGoStraightIn() {
        for key: Character in [".", ",", "(", "-", "\"", "'", "@", "#", "$", "+", "<", "~", "/", "_", "`",
                               " ", "0", "1", "9"] {
            XCTAssertTrue(ChinesePunctuation.goesStraightIn(key), "\(key)")
        }
        for key: Character in ["a", "Z", "中", "\t", "½", "١"] {
            XCTAssertFalse(ChinesePunctuation.goesStraightIn(key), "\(key)")
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
