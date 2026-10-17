import XCTest
@testable import FluentCore

final class ChineseComposerTests: XCTestCase {
    private let translator = ChineseTranslator(lexicon: makeLexicon([
        ("这", "zhe", 9000), ("着", "zhe", 3000), ("是", "shi", 8000), ("个", "ge", 7000),
        ("这是", "zhe shi", 900), ("这个", "zhe ge", 800), ("你", "ni", 7000), ("好", "hao", 6000),
        ("你好", "ni hao", 1000),
    ]))

    func testSelectingAWholeWordCommits() {
        var composer = ChineseComposer(keys: "nihc", translator: translator)
        XCTAssertEqual(composer.candidates.first?.text, "你好")
        XCTAssertEqual(composer.select(0), "你好")
    }

    func testPartialSelectionContinuesWithTheRest() {
        var composer = ChineseComposer(keys: "veuige", translator: translator)
        let index = composer.candidates.firstIndex { $0.text == "这是" }!
        XCTAssertNil(composer.select(index))
        XCTAssertEqual(composer.confirmedText, "这是")
        XCTAssertEqual(composer.remainingKeys, "ge")
        XCTAssertEqual(composer.preedit.converted, "这是")
        XCTAssertEqual(composer.preedit.raw, "ge")
        XCTAssertEqual(composer.candidates.first?.text, "个")
        XCTAssertEqual(composer.select(0), "这是个")
    }

    func testPunctuationLearnsTheHighlightedCandidateToo() {
        var composer = ChineseComposer(keys: "veuige", translator: translator)
        _ = composer.select(composer.candidates.firstIndex { $0.text == "这是" }!)
        XCTAssertEqual(composer.highlightedWords.map(\.text), ["这是", "个"])
        XCTAssertEqual(composer.highlightedWords.map(\.code), [ids("zhe shi"), ids("ge")])
    }

    func testBackspaceTakesBackAPickThenDeletesKeys() {
        var composer = ChineseComposer(keys: "veuige", translator: translator)
        _ = composer.select(composer.candidates.firstIndex { $0.text == "这是" }!)
        XCTAssertTrue(composer.backspace())
        XCTAssertEqual(composer.confirmedText, "")
        XCTAssertEqual(composer.remainingKeys, "veuige")
        XCTAssertTrue(composer.backspace())
        XCTAssertEqual(composer.keys, "veuig")
    }

    func testBackspaceAfterTypingDeletesAKeyFirst() {
        var composer = ChineseComposer(keys: "ve", translator: translator)
        composer.append("u")
        composer.append("i")
        _ = composer.select(composer.candidates.firstIndex { $0.text == "这" }!)
        composer.append("g")
        XCTAssertTrue(composer.backspace())  // deletes g
        XCTAssertEqual(composer.keys, "veui")
        XCTAssertEqual(composer.confirmedText, "这")
        XCTAssertTrue(composer.backspace())  // deletes i
        XCTAssertTrue(composer.backspace())  // deleting u empties the rest: reopens 这
        XCTAssertEqual(composer.confirmedText, "")
        XCTAssertEqual(composer.remainingKeys, "ve")
        XCTAssertTrue(composer.backspace())
        XCTAssertFalse(composer.backspace())
    }

    func testPagingAndHighlight() {
        var composer = ChineseComposer(keys: "v", translator: translator, pageSize: 2)
        XCTAssertEqual(composer.candidates.map(\.text), ["这", "着"])
        XCTAssertEqual(composer.pageCount, 1)
        composer = ChineseComposer(keys: "veu", translator: translator, pageSize: 1)
        XCTAssertEqual(composer.candidates.map(\.text), ["这是", "这", "着"])
        XCTAssertEqual(composer.page, 0)
        composer.turnPage(by: 1)
        XCTAssertEqual(composer.page, 1)
        XCTAssertEqual(composer.highlighted, 1)
        XCTAssertEqual(composer.pageCandidates.map(\.text), ["这"])
        composer.moveHighlight(by: 5)
        XCTAssertEqual(composer.highlighted, 2)
        composer.turnPage(by: -10)
        XCTAssertEqual(composer.highlighted, 0)
        XCTAssertEqual(composer.selectOnPage(0), "这是")
    }

    func testGridStaysPutWhileTheHighlightMoves() {
        var composer = ChineseComposer(keys: "veu", translator: translator, pageSize: 1)
        XCTAssertEqual(composer.gridRange(rows: 2), 0..<2)
        composer.moveHighlight(by: 1)
        XCTAssertEqual(composer.gridRange(rows: 2), 0..<2)
        composer.moveHighlight(by: 1)
        XCTAssertEqual(composer.gridRange(rows: 2), 2..<3)
    }

    func testPickedWords() {
        var composer = ChineseComposer(keys: "veuige", translator: translator)
        _ = composer.select(composer.candidates.firstIndex { $0.text == "这是" }!)
        _ = composer.select(0)
        XCTAssertEqual(composer.pickedWords.map(\.text), ["这是", "个"])
        XCTAssertEqual(composer.pickedWords.map(\.code), [ids("zhe shi"), ids("ge")])
    }

    func testCommitTextsWhenCutShort() {
        var composer = ChineseComposer(keys: "veuige", translator: translator)
        XCTAssertEqual(composer.interruptedText, "veuige")
        _ = composer.select(composer.candidates.firstIndex { $0.text == "这是" }!)
        XCTAssertEqual(composer.interruptedText, "这是ge")
        XCTAssertEqual(composer.highlightedText, "这是个")
    }

    func testKeysThatAreNoShuangpinAreOfferedAsTyped() {
        let composer = ChineseComposer(keys: "fk", translator: translator)
        XCTAssertEqual(composer.candidates.map(\.text), ["fk"])
        XCTAssertEqual(composer.candidates.first?.keyCount, 2)
    }
}
