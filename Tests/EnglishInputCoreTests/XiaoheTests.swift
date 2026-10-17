import XCTest
@testable import EnglishInputCore

final class XiaoheTests: XCTestCase {
    func testInitialsAndFinals() {
        XCTAssertEqual(Xiaohe.codes(for: "zhe"), ["ve"])
        XCTAssertEqual(Xiaohe.codes(for: "shi"), ["ui"])
        XCTAssertEqual(Xiaohe.codes(for: "chuang"), ["il"])
        XCTAssertEqual(Xiaohe.codes(for: "hao"), ["hc"])
        XCTAssertEqual(Xiaohe.codes(for: "jian"), ["jm"])
        XCTAssertEqual(Xiaohe.codes(for: "xiong"), ["xs"])
        XCTAssertEqual(Xiaohe.codes(for: "guai"), ["gk"])
        XCTAssertEqual(Xiaohe.codes(for: "jing"), ["jk"])
        XCTAssertEqual(Xiaohe.codes(for: "lve"), ["lt"])
        XCTAssertEqual(Xiaohe.codes(for: "nv"), ["nv"])
        XCTAssertEqual(Xiaohe.codes(for: "you"), ["yz"])
    }

    func testZeroInitialSyllables() {
        XCTAssertEqual(Xiaohe.codes(for: "a"), ["aa"])
        XCTAssertEqual(Xiaohe.codes(for: "e"), ["ee"])
        XCTAssertEqual(Xiaohe.codes(for: "ang"), ["ah"])
        XCTAssertEqual(Xiaohe.codes(for: "eng"), ["eg"])
        XCTAssertEqual(Xiaohe.codes(for: "er"), ["er"])
        XCTAssertEqual(Xiaohe.codes(for: "ai"), ["ai", "ad"])
        XCTAssertEqual(Xiaohe.codes(for: "ou"), ["ou", "oz"])
    }

    func testUmlautSyllablesAlsoTakeV() {
        XCTAssertEqual(Xiaohe.codes(for: "ju"), ["ju", "jv"])
        XCTAssertEqual(Xiaohe.codes(for: "yu"), ["yu", "yv"])
        XCTAssertEqual(Xiaohe.codes(for: "lu"), ["lu"])
    }

    func testEverySyllableHasACode() {
        for syllable in Pinyin.syllables {
            XCTAssertFalse(Xiaohe.codes(for: syllable).isEmpty, syllable)
        }
        XCTAssertEqual(Set(Pinyin.syllables.flatMap(Xiaohe.codes)).count, 423)
    }

    func testDecodePairs() {
        let decoding = Xiaohe.decode("veui")
        XCTAssertEqual(decoding.slots, [[Pinyin.id(of: "zhe")!], [Pinyin.id(of: "shi")!]])
        XCTAssertFalse(decoding.lastSlotIsPartial)
        XCTAssertTrue(decoding.isComplete)
        XCTAssertEqual(decoding.keyCount, 4)
    }

    func testDanglingKeyCompletesToEverySyllableItStarts() throws {
        let decoding = Xiaohe.decode("veu")
        XCTAssertEqual(decoding.slots.count, 2)
        XCTAssertTrue(decoding.lastSlotIsPartial)
        XCTAssertTrue(decoding.isComplete)
        let last = try XCTUnwrap(decoding.slots.last)
        XCTAssertTrue(last.contains(Pinyin.id(of: "shi")!))
        XCTAssertTrue(last.contains(Pinyin.id(of: "shuang")!))
        XCTAssertFalse(last.contains(Pinyin.id(of: "si")!))
        XCTAssertEqual(decoding.keyCount(ofSlots: 2), 3)
        XCTAssertEqual(decoding.keyCount(ofSlots: 1), 2)
    }

    func testAmbiguousPair() {
        XCTAssertEqual(Set(Xiaohe.syllables(forPair: "lo") ?? []),
                       [Pinyin.id(of: "lo")!, Pinyin.id(of: "luo")!])
    }

    func testInvalidPairStopsDecoding() {
        let decoding = Xiaohe.decode("nifkhc")
        XCTAssertEqual(decoding.slots.count, 1)
        XCTAssertEqual(decoding.keyCount, 2)
        XCTAssertFalse(decoding.isComplete)
        XCTAssertFalse(Xiaohe.isValid("word"))  // r·ai
        XCTAssertFalse(Xiaohe.isValid("test"))  // s·ue
        XCTAssertFalse(Xiaohe.isValid("Make"))
        XCTAssertFalse(Xiaohe.isValid(""))
        XCTAssertTrue(Xiaohe.isValid("make"))
        XCTAssertTrue(Xiaohe.isValid("hello"))
    }

    func testGroupedPreedit() {
        XCTAssertEqual(Xiaohe.grouped("veui"), "ve ui")
        XCTAssertEqual(Xiaohe.grouped("veu"), "ve u")
        XCTAssertEqual(Xiaohe.grouped("v"), "v")
        XCTAssertEqual(Xiaohe.grouped(""), "")
    }
}
