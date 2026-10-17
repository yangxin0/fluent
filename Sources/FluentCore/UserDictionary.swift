import Foundation

/// Words learned from the candidates you pick, ranked with librime's user
/// dictionary formulas (algo/dynamics.h): every commit bumps a word's count
/// and its "dee", a usage score that decays by e every 200 commits, so words
/// picked often and recently float up and unused ones fade.
///
/// Saved as TSV: a `#tick` line with the global commit counter, then
/// `text<TAB>pinyin syllables<TAB>commits<TAB>dee<TAB>tick` rows. Syllables
/// are spelled out so the file survives syllable-table changes.
public final class UserDictionary {
    struct Record: Equatable {
        var commits: Double
        var dee: Double
        var tick: Double
    }

    private struct Key: Hashable {
        var code: [SyllableID]
        var text: String
    }

    private var records: [Key: Record] = [:]
    /// Texts by code, and every prefix of a learned code, for walking the
    /// input like the system lexicon.
    private var textsByCode: [[SyllableID]: [String]] = [:]
    private var prefixes: Set<[SyllableID]> = []
    /// Global commit counter, librime's `/tick`.
    public private(set) var tick: Double = 0

    /// Words longer than this are not learned (librime's limit is similar).
    static let maxLearnedSyllables = 8

    /// Where the IME keeps the learned words.
    public static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fluent/xiaohe-user.tsv")

    /// Posted (distributed) by the Settings app to make the running IME
    /// forget every learned word.
    public static let forgetNotification = "com.yangxin.inputmethod.Fluent.forgetLearnedWords"

    public init() {}

    public var count: Int { records.count }

    /// Forgets every learned word.
    public func reset() {
        records = [:]
        textsByCode = [:]
        prefixes = []
        tick = 0
    }

    /// Learns the words of one commit: each picked part, and when the commit
    /// was built from several picks, the whole phrase as a new word. False
    /// when there was nothing to learn (keys offered as typed, long words).
    @discardableResult
    public func learn(_ words: [(text: String, code: [SyllableID])]) -> Bool {
        let words = words.filter {
            !$0.code.isEmpty && !$0.text.isEmpty && $0.code.count <= Self.maxLearnedSyllables
        }
        guard !words.isEmpty else { return false }
        tick += 1
        for word in words {
            bump(text: word.text, code: word.code)
        }
        let code = words.flatMap(\.code)
        if words.count > 1, code.count <= Self.maxLearnedSyllables {
            bump(text: words.map(\.text).joined(), code: code)
        }
        return true
    }

    private func bump(text: String, code: [SyllableID]) {
        let key = Key(code: code, text: text)
        var record = records[key] ?? Record(commits: 0, dee: 0, tick: tick)
        record.commits += 1
        record.dee = Self.decayed(record.dee, from: record.tick, to: tick) + 1
        record.tick = tick
        insert(key, record)
    }

    private func insert(_ key: Key, _ record: Record) {
        if records.updateValue(record, forKey: key) == nil {
            textsByCode[key.code, default: []].append(key.text)
            for length in 1...key.code.count {
                prefixes.insert(Array(key.code.prefix(length)))
            }
        }
    }

    /// Whether some learned word's code starts with `code`.
    public func hasPrefix(_ code: [SyllableID]) -> Bool { prefixes.contains(code) }

    /// Learned words typed exactly as `code`, best first, with their weights
    /// on the lexicon's log scale.
    public func words(for code: [SyllableID]) -> [(text: String, weight: Float)] {
        guard let texts = textsByCode[code] else { return [] }
        return texts.compactMap { text in
            records[Key(code: code, text: text)].map { (text, weight(of: $0)) }
        }
        .sorted { $0.weight > $1.weight }
    }

    // MARK: - librime's formulas

    /// `formula_d`: the dee carried from `then` to `now`.
    static func decayed(_ dee: Double, from then: Double, to now: Double) -> Double {
        dee * exp((then - now) / 200)
    }

    /// `formula_p` with no prior, as a log weight.
    func weight(of record: Record) -> Float {
        let present = max(tick, 1)
        let dee = Self.decayed(record.dee, from: record.tick, to: present)
        let usage = record.commits / present
        let m = usage * pow(1 - exp(-present / 10_000), 10)
        let scale = 1 / (1 - exp(-0.005))
        let p = dee < 20 ? m + (0.5 - m) * (dee / scale) : m + (1 - m) * (pow(4, dee / scale) - 1) / 3
        return Float(log(max(p, .leastNormalMagnitude)))
    }

    // MARK: - Persistence

    public convenience init(contentsOf url: URL) throws {
        self.init()
        // Lossy, so one bad byte costs a row rather than every learned word.
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#tick\t") {
                tick = Double(line.dropFirst(6)) ?? 0
                continue
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let commits = Double(fields[2]), let dee = Double(fields[3]), let then = Double(fields[4])
            else { continue }
            let code = fields[1].split(separator: " ").compactMap { Pinyin.id(of: String($0)) }
            guard !code.isEmpty, code.count == fields[1].split(separator: " ").count else { continue }
            insert(Key(code: code, text: String(fields[0])), Record(commits: commits, dee: dee, tick: then))
        }
    }

    public func serialized() -> String {
        var lines = ["#tick\t\(tick)"]
        for (key, record) in records.sorted(by: { $0.value.tick > $1.value.tick }) {
            let pinyin = key.code.map { Pinyin.syllables[Int($0)] }.joined(separator: " ")
            lines.append("\(key.text)\t\(pinyin)\t\(record.commits)\t\(record.dee)\t\(record.tick)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
