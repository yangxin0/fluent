import XCTest
@testable import FluentCore

final class XiaoheTranslatorTests: XCTestCase {
    private let translator = XiaoheTranslator(lexicon: makeLexicon([
        ("这", "zhe", 9000), ("着", "zhe", 3000), ("是", "shi", 8000), ("时", "shi", 4000),
        ("书", "shu", 3000), ("你", "ni", 7000), ("好", "hao", 6000), ("餮", "tie", 10),
        ("这是", "zhe shi", 900), ("这时", "zhe shi", 500), ("这时候", "zhe shi hou", 200),
        ("你好", "ni hao", 1000), ("罗", "luo", 500), ("咯", "lo", 50), ("咯", "luo", 10),
    ]))

    private func texts(_ keys: String) -> [String] {
        translator.candidates(for: keys).map(\.text)
    }

    func testLongerWordsComeFirstThenByWeight() {
        let candidates = translator.candidates(for: "veui")
        XCTAssertEqual(candidates.map(\.text), ["这是", "这时", "这时候", "这", "着"])
        XCTAssertEqual(candidates.map(\.keyCount), [4, 4, 4, 2, 2])
    }

    func testPredictionIsPenalizedBelowExactWords() {
        let candidates = translator.candidates(for: "veui")
        XCTAssertLessThan(candidates[2].weight, candidates[1].weight)
        XCTAssertEqual(candidates[2].code, ids("zhe shi hou"))
    }

    func testSentenceWhenNoWordCoversTheInput() throws {
        let first = try XCTUnwrap(translator.candidates(for: "veuiuu").first)
        XCTAssertEqual(first.text, "这是书")  // 这是 + 书 beats 这 + 是 + 书
        XCTAssertEqual(first.keyCount, 6)
        XCTAssertEqual(first.code, ids("zhe shi shu"))
        XCTAssertEqual(Array(texts("veuiuu").dropFirst().prefix(2)), ["这是", "这时"])
    }

    func testDanglingKeyCompletes() throws {
        let first = try XCTUnwrap(translator.candidates(for: "nih").first)
        XCTAssertEqual(first.text, "你好")
        XCTAssertEqual(first.keyCount, 3)
        XCTAssertEqual(texts("nih").last, "你")
    }

    func testRareCharacterShowsItsPinyin() throws {
        let candidate = try XCTUnwrap(translator.candidates(for: "tp").first)
        XCTAssertEqual(candidate.text, "餮")
        XCTAssertEqual(candidate.comment, "tie")
        XCTAssertNil(translator.candidates(for: "ve").first?.comment)
    }

    func testAmbiguousPairOffersBothReadingsOnce() {
        XCTAssertEqual(texts("lo"), ["罗", "咯"])
    }

    func testLearnedWordsComeFirstAmongTheirLength() {
        let user = UserDictionary()
        user.learn([("这时", ids("zhe shi"))])
        user.learn([("着", ids("zhe"))])
        translator.userDictionary = user
        defer { translator.userDictionary = nil }
        XCTAssertEqual(texts("veui"), ["这时", "这是", "这时候", "着", "这"])
    }

    func testLearnedPhraseReplacesTheSentence() {
        let user = UserDictionary()
        user.learn([("这是", ids("zhe shi")), ("书", ids("shu"))])
        translator.userDictionary = user
        defer { translator.userDictionary = nil }
        let first = translator.candidates(for: "veuiuu").first
        XCTAssertEqual(first?.text, "这是书")
        XCTAssertEqual(first?.code, ids("zhe shi shu"))
        XCTAssertEqual(texts("veuiuu").filter { $0 == "这是书" }.count, 1)
    }

    func testLearnedWordsJoinSentences() {
        let user = UserDictionary()
        user.learn([("著", ids("zhe"))])
        translator.userDictionary = user
        defer { translator.userDictionary = nil }
        XCTAssertEqual(texts("veuu").first, "著书")
    }

    func testNotShuangpinGivesNothing() {
        XCTAssertEqual(texts("fk"), [])
        XCTAssertEqual(texts(""), [])
    }
}
