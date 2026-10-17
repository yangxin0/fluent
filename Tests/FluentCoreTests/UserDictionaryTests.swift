import XCTest
@testable import FluentCore

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

    func testLongPicksAreNotLearned() {
        let user = UserDictionary()
        let sentence = ids("wo xian zai jiu qu xue xiao kan ta")  // 9 syllables
        user.learn([("我现在就去学校看他", sentence)])
        XCTAssertEqual(user.count, 0)
        user.learn([("我现在就去学校看他", sentence), ("吧", ids("ba"))])
        XCTAssertEqual(user.words(for: ids("ba")).map(\.text), ["吧"])
        XCTAssertEqual(user.count, 1)
    }

    func testLoadsWindowsLineEndingsAndBadBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("user-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data("#tick\t3\r\n你好\tni hao\t2\t1.5\t3\r\n".utf8)
        data += [0xFF, 0x0A]  // a damaged row
        data += Data("这是\tzhe shi\t1\t1\t2\n".utf8)
        try data.write(to: url)
        let loaded = try UserDictionary(contentsOf: url)
        XCTAssertEqual(loaded.tick, 3)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.words(for: ids("ni hao")).map(\.text), ["你好"])
    }

    func testResetForgetsEverything() {
        let user = UserDictionary()
        user.learn([("这是", ids("zhe shi")), ("个", ids("ge"))])
        user.reset()
        XCTAssertEqual(user.count, 0)
        XCTAssertEqual(user.tick, 0)
        XCTAssertFalse(user.hasPrefix(ids("zhe")))
        XCTAssertTrue(user.words(for: ids("zhe shi")).isEmpty)
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
