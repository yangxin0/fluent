import XCTest
@testable import FluentCore

final class FullPinyinTests: XCTestCase {
    private let layout = FullPinyinLayout()

    /// (end, syllables) of the edges leaving `position`, as pinyin.
    private func edges(_ graph: SyllableGraph, at position: Int) -> Set<String> {
        Set((graph.edges[position] ?? []).flatMap { edge in
            edge.syllables.map { "\(edge.end):\(Pinyin.syllables[Int($0)])" }
        })
    }

    func testWholeSyllables() {
        let graph = layout.graph(for: "zhongguo")
        XCTAssertTrue(graph.isComplete)
        XCTAssertEqual(edges(graph, at: 0), ["5:zhong"])
        // zhong guo, and zhong gu o: `o` is a syllable too.
        XCTAssertEqual(edges(graph, at: 5), ["8:guo", "7:gu"])
    }

    func testAmbiguousSplitKeepsBothReadings() {
        let graph = layout.graph(for: "xian")
        XCTAssertEqual(edges(graph, at: 0), ["4:xian", "2:xi"])
        XCTAssertEqual(edges(graph, at: 2), ["4:an"])
    }

    func testSeparatorForcesTheSplit() {
        let graph = layout.graph(for: "xi'an")
        XCTAssertTrue(graph.isComplete)
        XCTAssertEqual(edges(graph, at: 0), ["3:xi"])
        XCTAssertEqual(edges(graph, at: 3), ["5:an"])
        XCTAssertTrue(layout.graph(for: "xi'").isComplete)
    }

    func testInitialsOnly() throws {
        let graph = layout.graph(for: "zg")
        XCTAssertTrue(graph.isComplete)
        let first = try XCTUnwrap(graph.edges[0]?.first)
        XCTAssertEqual(first.kind, .abbreviation)
        XCTAssertTrue(first.syllables.contains(Pinyin.id(of: "zhong")!))
        XCTAssertTrue(layout.graph(for: "zhg").isComplete)  // zh as one initial
        XCTAssertFalse(FullPinyinLayout(abbreviations: false).graph(for: "zg").isComplete)
    }

    func testInitialsDropOutWhereWholeSpellingsFit() {
        let graph = layout.graph(for: "nihao")
        for list in graph.edges.values {
            XCTAssertTrue(list.allSatisfy { $0.kind == .normal })
        }
    }

    func testUnfinishedLastSyllableCompletes() throws {
        let graph = FullPinyinLayout(abbreviations: false).graph(for: "zhon")
        XCTAssertTrue(graph.isComplete)
        let edge = try XCTUnwrap(graph.edges[0]?.first)
        XCTAssertEqual(edge.kind, .completion)
        XCTAssertTrue(edge.syllables.contains(Pinyin.id(of: "zhong")!))
    }

    func testFuzzyPairs() {
        let fuzzy = FullPinyinLayout(fuzzy: ["zh=z", "an=ang"])
        XCTAssertTrue(edges(fuzzy.graph(for: "zi"), at: 0).isSuperset(of: ["2:zi", "2:zhi"]))
        XCTAssertTrue(edges(fuzzy.graph(for: "zhi"), at: 0).isSuperset(of: ["3:zhi", "3:zi"]))
        XCTAssertTrue(edges(fuzzy.graph(for: "jian"), at: 0).contains("4:jiang"))
        XCTAssertFalse(edges(layout.graph(for: "zi"), at: 0).contains("2:zhi"))
    }

    func testUmlautAlsoTypedWithU() {
        XCTAssertTrue(edges(layout.graph(for: "lue"), at: 0).contains("3:lve"))
    }

    func testNotPinyin() {
        XCTAssertFalse(layout.isValid("iphone"))  // no syllable starts with i
        XCTAssertFalse(layout.isValid("Ni"))
        XCTAssertFalse(layout.isValid(""))
    }

    func testGroupedFollowsTheBestReading() {
        XCTAssertEqual(layout.grouped("zhongguo"), "zhong guo")
        XCTAssertEqual(layout.grouped("xian"), "xian")
        XCTAssertEqual(layout.grouped("xi'an"), "xi'an")
        XCTAssertEqual(layout.grouped("zg"), "z g")
        XCTAssertEqual(layout.grouped("nihaoi"), "ni hao i")  // keys past the last syllable stay as typed
    }

    func testTranslatorWithFullPinyin() {
        let translator = ChineseTranslator(lexicon: makeLexicon([
            ("你", "ni", 7000), ("好", "hao", 6000), ("你好", "ni hao", 1000),
            ("先", "xian", 9000), ("西", "xi", 5000), ("安", "an", 4000), ("西安", "xi an", 800),
            ("中", "zhong", 9000), ("国", "guo", 8000), ("中国", "zhong guo", 3000),
        ]), layout: layout)
        XCTAssertEqual(translator.candidates(for: "nihao").first?.text, "你好")
        XCTAssertEqual(translator.candidates(for: "nh").first?.text, "你好")
        XCTAssertEqual(translator.candidates(for: "zhongg").first?.text, "中国")
        let xian = translator.candidates(for: "xian").map(\.text)
        XCTAssertEqual(xian.first, "先")  // by weight, though 西安 also covers all four keys
        XCTAssertTrue(xian.contains("西安"))
        XCTAssertEqual(translator.candidates(for: "xi'an").first?.text, "西安")
    }

    func testEnglishWordsStayEnglishFirst() {
        let english = EnglishWords(["hang", "change"])
        XCTAssertEqual(ChinesePolicy.rank(run: "hang", context: .fresh, english: english, layout: layout),
                       .alternatives)
        XCTAssertEqual(ChinesePolicy.rank(run: "nihao", context: .fresh, english: english, layout: layout),
                       .primary)
        XCTAssertEqual(ChinesePolicy.rank(run: "iphone", context: .fresh, english: english, layout: layout),
                       .none)
    }

    func testStrayKeyAfterPinyinStaysChinese() {
        let english = EnglishWords(["hanging", "beautiful"])
        func rank(_ run: String, _ context: RunContext = .fresh) -> ChineseRank {
            ChinesePolicy.rank(run: run, context: context, english: english, layout: layout)
        }
        XCTAssertEqual(rank("woxianzaijiui"), .primary)  // no syllable starts with i
        XCTAssertEqual(rank("woxianzaijiuiqu"), .primary)  // keys after it stay as typed too
        XCTAssertEqual(rank("woxianzaijiui", .afterChinese), .primary)
        XCTAssertEqual(rank("woxianzaijiui", .afterEnglish), .none)
        XCTAssertEqual(rank("nginx"), .none)  // `ng` reads only as initials
        XCTAssertEqual(rank("hanging"), .none)
        XCTAssertEqual(rank("hanging", .afterChinese), .none)  // `hang` is pinyin, the run is English
        XCTAssertEqual(rank("beautiful"), .none)
    }

    func testPickingBeforeAStrayKeyLeavesItToFix() {
        let translator = ChineseTranslator(lexicon: makeLexicon([
            ("我", "wo", 9000), ("现在", "xian zai", 5000), ("就", "jiu", 8000),
        ]), layout: layout)
        var composer = ChineseComposer(keys: "woxianzaijiui", translator: translator)
        XCTAssertEqual(composer.preedit.raw, "wo xian zai jiu i")
        XCTAssertEqual(composer.candidates.first?.text, "我现在就")
        XCTAssertNil(composer.select(0))
        XCTAssertEqual(composer.remainingKeys, "i")
        XCTAssertEqual(composer.select(0), "我现在就i")  // the stray key as typed
    }
}
