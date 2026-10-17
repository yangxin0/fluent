import XCTest
@testable import FluentCore

/// A lexicon from `(text, space-separated pinyin, raw weight)` rows.
func makeLexicon(_ rows: [(String, String, Double)]) -> Lexicon {
    Lexicon(entries: rows.map { text, pinyin, weight in
        Lexicon.Entry(text: text, code: pinyin.split(separator: " ").map { Pinyin.id(of: String($0))! },
                      weight: Lexicon.normalizedWeight(weight))
    })
}

func ids(_ pinyin: String) -> [SyllableID] {
    pinyin.split(separator: " ").map { Pinyin.id(of: String($0))! }
}

final class LexiconTests: XCTestCase {
    private let lexicon = makeLexicon([
        ("这时", "zhe shi", 500), ("这", "zhe", 9000), ("这是", "zhe shi", 900),
        ("着", "zhe", 3000), ("是", "shi", 8000), ("这时候", "zhe shi hou", 200),
    ])

    func testRoundTrip() throws {
        let copy = try Lexicon(data: Lexicon.encode((0..<lexicon.count).map(lexicon.entry(at:))))
        XCTAssertEqual(copy.count, 6)
        XCTAssertEqual((0..<copy.count).map(copy.entry(at:)), (0..<lexicon.count).map(lexicon.entry(at:)))
    }

    func testExactMatchesAreByWeight() throws {
        let range = try XCTUnwrap(lexicon.range(forPrefix: ids("zhe shi")))
        XCTAssertEqual(lexicon.exactMatches(in: range).map(lexicon.text(at:)), ["这是", "这时"])
        let single = try XCTUnwrap(lexicon.range(forPrefix: ids("zhe")))
        XCTAssertEqual(lexicon.exactMatches(in: single).map(lexicon.text(at:)), ["这", "着"])
    }

    func testPrefixRangeHoldsLongerWords() throws {
        let range = try XCTUnwrap(lexicon.range(forPrefix: ids("zhe shi")))
        XCTAssertEqual((range.lower..<range.upper).map(lexicon.text(at:)), ["这是", "这时", "这时候"])
        XCTAssertNil(lexicon.range(forPrefix: ids("zhe hou")))
        XCTAssertNil(lexicon.range(forPrefix: ids("ni")))
    }

    func testWeightIsLibrimeLogScale() {
        XCTAssertEqual(Lexicon.normalizedWeight(1e8), 0, accuracy: 1e-6)
        XCTAssertEqual(Lexicon.normalizedWeight(1e6), Float(log(0.01)), accuracy: 1e-5)
    }

    func testRejectsBadData() {
        XCTAssertThrowsError(try Lexicon(data: Data("nope".utf8)))
        var data = Lexicon.encode([])
        data[8] ^= 0xFF  // syllable table hash
        XCTAssertThrowsError(try Lexicon(data: data)) { error in
            XCTAssertEqual(error as? Lexicon.LoadError, .staleSyllableTable)
        }
        let full = Lexicon.encode((0..<lexicon.count).map(lexicon.entry(at:)))
        XCTAssertThrowsError(try Lexicon(data: full.prefix(full.count - 1))) { error in
            XCTAssertEqual(error as? Lexicon.LoadError, .truncated)
        }
    }
}
