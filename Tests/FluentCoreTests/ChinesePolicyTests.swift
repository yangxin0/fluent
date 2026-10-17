import XCTest
@testable import FluentCore

final class ChinesePolicyTests: XCTestCase {
    private let english = EnglishWords(["make", "like", "hello", "nice", "UI", "Mac", "test"])

    func testWordList() {
        XCTAssertTrue(english.contains("make"))
        XCTAssertFalse(english.contains("mak"))
        XCTAssertTrue(english.hasWord(withPrefix: "mak"))
        XCTAssertTrue(english.hasWord(withPrefix: "make"))
        XCTAssertFalse(english.hasWord(withPrefix: "veu"))
        // Capitalized entries are left out: `ui` is 是.
        XCTAssertFalse(english.contains("ui"))
        XCTAssertFalse(english.contains("mac"))
        XCTAssertEqual(english.count, 5)
    }

    func testFreshInputIsChineseOnlyWhenNoEnglishWordStartsThatWay() {
        XCTAssertEqual(ChinesePolicy.rank(run: "veui", context: .fresh, english: english), .primary)
        XCTAssertEqual(ChinesePolicy.rank(run: "nihc", context: .fresh, english: english), .primary)
        XCTAssertEqual(ChinesePolicy.rank(run: "ni", context: .fresh, english: english), .alternatives)
        XCTAssertEqual(ChinesePolicy.rank(run: "make", context: .fresh, english: english), .alternatives)
    }

    func testNotShuangpinIsEnglishOnly() {
        XCTAssertEqual(ChinesePolicy.rank(run: "test", context: .fresh, english: english), .none)
        XCTAssertEqual(ChinesePolicy.rank(run: "Veui", context: .fresh, english: english), .none)
        XCTAssertEqual(ChinesePolicy.rank(run: "", context: .afterChinese, english: english), .none)
    }

    func testStrayPairAfterShuangpinStaysChinese() {
        XCTAssertEqual(ChinesePolicy.rank(run: "veuifk", context: .fresh, english: english), .primary)
        XCTAssertEqual(ChinesePolicy.rank(run: "nifk", context: .fresh, english: english), .none)  // ni → nice
    }

    func testAfterChineseOnlyWholeEnglishWordsGoFirst() {
        XCTAssertEqual(ChinesePolicy.rank(run: "ni", context: .afterChinese, english: english), .primary)
        XCTAssertEqual(ChinesePolicy.rank(run: "make", context: .afterChinese, english: english), .alternatives)
    }

    func testEnglishSentencesGetNoChinese() {
        XCTAssertEqual(ChinesePolicy.rank(run: "rela", context: .afterEnglish, english: english), .none)
        XCTAssertEqual(ChinesePolicy.rank(run: "make", context: .afterEnglish, english: english), .none)
        XCTAssertEqual(ChinesePolicy.rank(run: "veui", context: .afterEnglish, english: english), .none)
    }

    func testRunAtCursor() {
        XCTAssertEqual(ChinesePolicy.run(in: "I make", cursor: 6), "make")
        XCTAssertEqual(ChinesePolicy.run(in: "I make ", cursor: 7), "")
        XCTAssertEqual(ChinesePolicy.run(in: "veui", cursor: 4), "veui")
        XCTAssertEqual(ChinesePolicy.run(in: "veui", cursor: 2), "")  // inside a word
        XCTAssertEqual(ChinesePolicy.run(in: "a,b", cursor: 3), "b")
        XCTAssertEqual(ChinesePolicy.run(in: "", cursor: 0), "")
    }
}
