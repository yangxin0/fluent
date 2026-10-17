import XCTest
@testable import EnglishInputCore

final class UserDictionaryTests: XCTestCase {
    func testLearnsPicksAndThePhraseTheyMake() {
        let user = UserDictionary()
        user.learn([("这是", ids("zhe shi")), ("个", ids("ge"))])
        XCTAssertEqual(user.tick, 1)
        XCTAssertEqual(user.words(for: ids("zhe shi")).map(\.text), ["这是"])
        XCTAssertEqual(user.words(for: ids("zhe shi ge")).map(\.text), ["这是个"])
        XCTAssertTrue(user.hasPrefix(ids("zhe")))
        XCTAssertFalse(user.hasPrefix(ids("shi")))
    }

    func testKeysOfferedAsTypedAreNotLearned() {
        let user = UserDictionary()
        user.learn([("fk", [])])
        XCTAssertEqual(user.count, 0)
        XCTAssertEqual(user.tick, 0)
    }

    func testFrequentAndRecentWordsRankHigher() {
        let user = UserDictionary()
        user.learn([("这时", ids("zhe shi"))])
        user.learn([("这是", ids("zhe shi"))])
        user.learn([("这是", ids("zhe shi"))])
        XCTAssertEqual(user.words(for: ids("zhe shi")).map(\.text), ["这是", "这时"])
        // Long unused, a word fades below one picked since.
        for _ in 0..<600 { user.learn([("个", ids("ge"))]) }
        user.learn([("这时", ids("zhe shi"))])
        XCTAssertEqual(user.words(for: ids("zhe shi")).map(\.text), ["这时", "这是"])
    }

    func testDeeDecaysByEEvery200Commits() {
        XCTAssertEqual(UserDictionary.decayed(1, from: 0, to: 200), exp(-1), accuracy: 1e-12)
    }

    func testRoundTrip() throws {
        let user = UserDictionary()
        user.learn([("你好", ids("ni hao"))])
        user.learn([("这是", ids("zhe shi")), ("个", ids("ge"))])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("user-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        try user.serialized().write(to: url, atomically: true, encoding: .utf8)
        let loaded = try UserDictionary(contentsOf: url)
        XCTAssertEqual(loaded.tick, 2)
        XCTAssertEqual(loaded.count, 4)
        XCTAssertEqual(loaded.words(for: ids("zhe shi ge")).map(\.text), ["这是个"])
        XCTAssertEqual(loaded.words(for: ids("ni hao")).first?.weight, user.words(for: ids("ni hao")).first?.weight)
    }
}
