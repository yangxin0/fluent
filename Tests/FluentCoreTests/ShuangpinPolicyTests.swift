import XCTest
@testable import FluentCore

final class ShuangpinPolicyTests: XCTestCase {
    func testShuangpinIsOfferedChinese() {
        XCTAssertTrue(ShuangpinPolicy.offersChinese(run: "nihc", afterEnglishWords: false))
        XCTAssertTrue(ShuangpinPolicy.offersChinese(run: "make", afterEnglishWords: false))
        XCTAssertTrue(ShuangpinPolicy.offersChinese(run: "bbq", afterEnglishWords: false))
    }

    func testNotShuangpinIsEnglishOnly() {
        XCTAssertFalse(ShuangpinPolicy.offersChinese(run: "test", afterEnglishWords: false))  // s·ue
        XCTAssertFalse(ShuangpinPolicy.offersChinese(run: "Veui", afterEnglishWords: false))
        XCTAssertFalse(ShuangpinPolicy.offersChinese(run: "", afterEnglishWords: false))
    }

    func testEnglishSentencesGetNoChinese() {
        XCTAssertFalse(ShuangpinPolicy.offersChinese(run: "rela", afterEnglishWords: true))
        XCTAssertFalse(ShuangpinPolicy.offersChinese(run: "veui", afterEnglishWords: true))
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
