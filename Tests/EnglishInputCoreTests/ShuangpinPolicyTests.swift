import XCTest
@testable import EnglishInputCore

final class ShuangpinPolicyTests: XCTestCase {
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
        XCTAssertEqual(ShuangpinPolicy.rank(run: "veui", context: .fresh, english: english), .primary)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "nihc", context: .fresh, english: english), .primary)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "ni", context: .fresh, english: english), .alternatives)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "make", context: .fresh, english: english), .alternatives)
    }

    func testNotShuangpinIsEnglishOnly() {
        XCTAssertEqual(ShuangpinPolicy.rank(run: "test", context: .fresh, english: english), .none)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "Veui", context: .fresh, english: english), .none)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "", context: .afterChinese, english: english), .none)
    }

    func testAfterChineseOnlyWholeEnglishWordsGoFirst() {
        XCTAssertEqual(ShuangpinPolicy.rank(run: "ni", context: .afterChinese, english: english), .primary)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "make", context: .afterChinese, english: english), .alternatives)
    }

    func testInsideEnglishTextChineseIsOnlyAnAlternative() {
        XCTAssertEqual(ShuangpinPolicy.rank(run: "rela", context: .afterEnglish, english: english), .alternatives)
        XCTAssertEqual(ShuangpinPolicy.rank(run: "veui", context: .afterEnglish, english: english), .alternatives)
    }

    func testRunAtCursor() {
        XCTAssertEqual(ShuangpinPolicy.run(in: "I make", cursor: 6), "make")
        XCTAssertEqual(ShuangpinPolicy.run(in: "I make ", cursor: 7), "")
        XCTAssertEqual(ShuangpinPolicy.run(in: "veui", cursor: 4), "veui")
        XCTAssertEqual(ShuangpinPolicy.run(in: "veui", cursor: 2), "")  // inside a word
        XCTAssertEqual(ShuangpinPolicy.run(in: "a,b", cursor: 3), "b")
        XCTAssertEqual(ShuangpinPolicy.run(in: "", cursor: 0), "")
    }
}
