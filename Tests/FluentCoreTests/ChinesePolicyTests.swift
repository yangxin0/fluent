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

    func testYourWordsAreEnglishToo() {
        var words = EnglishWords(["make", "copy"])
        // `copatent` is valid shuangpin and no dictionary word starts with `copa`.
        XCTAssertEqual(ChinesePolicy.rank(run: "copa", context: .fresh, english: words), .primary)
        XCTAssertTrue(words.add("Copatent"))
        XCTAssertFalse(words.add("copatent"))  // known already
        XCTAssertFalse(words.add("make"))  // a dictionary word
        XCTAssertFalse(words.add("co'pa"))  // not a word
        XCTAssertFalse(words.add("x"))
        XCTAssertEqual(words.yours, ["copatent"])
        XCTAssertTrue(words.contains("copatent"))
        XCTAssertTrue(words.hasWord(withPrefix: "copa"))
        XCTAssertEqual(ChinesePolicy.rank(run: "copa", context: .fresh, english: words), .alternatives)
        XCTAssertEqual(ChinesePolicy.rank(run: "copatent", context: .afterChinese, english: words), .alternatives)
        XCTAssertEqual(words.count, 2)  // the dictionary alone
    }

    func testYourWordsFile() {
        XCTAssertEqual(EnglishWords.yours(from: "Copatent\n\n  fluent \nnot a word\nab\r\nx\ncopatent\n"),
                       ["ab", "copatent", "fluent"])
        XCTAssertEqual(EnglishWords.serialized(["ab", "copatent"]), "ab\ncopatent\n")
        var words = EnglishWords([String]())
        words.setYours(["Zeta", "alpha", "alpha", "1st"])
        XCTAssertEqual(words.yours, ["alpha", "zeta"])
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

    func testACapitalAfterShuangpinIsEnglish() {
        for context in [RunContext.fresh, .afterChinese] {
            XCTAssertEqual(ChinesePolicy.rank(run: "nihcK", context: context, english: english), .none)
            XCTAssertEqual(ChinesePolicy.rank(run: "veuiKevin", context: context, english: english), .none)
        }
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

    func testTwoEnglishWordsAreASentenceEvenAfterChinese() {
        func context(_ prefix: String) -> RunContext {
            ChinesePolicy.context(prefix: prefix, afterChineseCommit: true)
        }
        XCTAssertEqual(context(""), .afterChinese)
        XCTAssertEqual(context("bug "), .afterChinese)  // 这个 bug 修好了
        XCTAssertEqual(context("all relays are deployed in "), .afterEnglish)
        XCTAssertEqual(context("2. bug "), .afterChinese)  // a list number is no word
        XCTAssertEqual(ChinesePolicy.context(prefix: "  ", afterChineseCommit: false), .fresh)
        XCTAssertEqual(ChinesePolicy.context(prefix: "I ", afterChineseCommit: false), .afterEnglish)
        // So `china` at the end of an English sentence stays English.
        XCTAssertEqual(ChinesePolicy.rank(run: "china", context: context("all relays are deployed in "),
                                          english: english), .none)
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
