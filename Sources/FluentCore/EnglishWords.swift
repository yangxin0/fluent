import Foundation

/// Lowercase English words (rime-ice's English dictionary, compiled by
/// `make dict`), for telling English apart from shuangpin keys, plus your
/// own: words the dictionary lacks, such as product names.
public struct EnglishWords {
    private let words: [String]
    /// Your words, sorted: added in Settings ▸ English, or inserted as typed
    /// from the Chinese bar. Kept apart from the dictionary.
    public private(set) var yours: [String] = []

    /// Words in any order and case; only all-lowercase a–z words are kept,
    /// since a run typed with capitals is English anyway and lowercasing
    /// acronyms would claim common shuangpin (`UI` → `ui` = 是).
    public init<S: Sequence>(_ words: S) where S.Element: StringProtocol {
        var kept = Set<String>()
        for word in words
        where !word.isEmpty && word.utf8.allSatisfy({ $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") }) {
            kept.insert(String(word))
        }
        self.words = kept.sorted()
    }

    /// One word per line.
    public init(contentsOf url: URL) throws {
        self.init(try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline))
    }

    public var count: Int { words.count }

    /// Where your words are kept (docs/config.md); Settings edits the file
    /// too.
    public static let yoursFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fluent/english-words.txt")

    public func contains<S: StringProtocol>(_ word: S) -> Bool {
        Self.contains(word, in: words) || Self.contains(word, in: yours)
    }

    /// Whether some word starts with `prefix` (or is it).
    public func hasWord<S: StringProtocol>(withPrefix prefix: S) -> Bool {
        Self.hasWord(withPrefix: prefix, in: words) || Self.hasWord(withPrefix: prefix, in: yours)
    }

    /// Adds `word` to yours, lowercased. False when it is no word (letters
    /// a–z, two or more) or one already known.
    @discardableResult
    public mutating func add<S: StringProtocol>(_ word: S) -> Bool {
        guard let word = Self.normalized(word), !contains(word) else { return false }
        yours.insert(word, at: Self.lowerBound(word, in: yours))
        return true
    }

    /// Replaces your words with `list`, keeping only words.
    public mutating func setYours<S: Sequence>(_ list: S) where S.Element: StringProtocol {
        yours = Array(Set(list.compactMap(Self.normalized))).sorted()
    }

    /// A word as kept: lowercased, and only letters a–z, two or more.
    public static func normalized<S: StringProtocol>(_ word: S) -> String? {
        let lower = word.trimmingCharacters(in: .whitespaces).lowercased()
        guard lower.count >= 2,
              lower.utf8.allSatisfy({ $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") }) else { return nil }
        return lower
    }

    /// Your words file (docs/config.md): one word per line.
    public static func yours(from text: String) -> [String] {
        Array(Set(text.split(whereSeparator: \.isNewline).compactMap(normalized))).sorted()
    }

    public static func serialized(_ yours: [String]) -> String {
        yours.map { $0 + "\n" }.joined()
    }

    private static func contains<S: StringProtocol>(_ word: S, in list: [String]) -> Bool {
        let index = lowerBound(word, in: list)
        return index < list.count && list[index] == word
    }

    private static func hasWord<S: StringProtocol>(withPrefix prefix: S, in list: [String]) -> Bool {
        let index = lowerBound(prefix, in: list)
        return index < list.count && list[index].hasPrefix(prefix)
    }

    private static func lowerBound<S: StringProtocol>(_ key: S, in list: [String]) -> Int {
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// Where Chinese candidates go for the letters typed at the caret. English
/// is the main language, so Chinese only goes first when the keys cannot be
/// (the start of) an English word.
public enum ChineseRank: Equatable {
    /// Not pinyin (or typed with capitals): English only.
    case none
    /// English first; the Chinese readings are alternatives.
    case alternatives
    /// Chinese first, in the candidate bar.
    case primary
}

/// What the composition holds before the letters at the caret.
public enum RunContext: Equatable {
    /// Nothing (or only whitespace), and the last text committed was not
    /// Chinese.
    case fresh
    /// Since a Chinese commit, with nothing typed before the letters or
    /// one English word embedded in the Chinese text (`这个 bug 修好了`).
    case afterChinese
    /// English typed earlier in this composition, not right after Chinese
    /// text, or two or more words even after it: an English sentence.
    case afterEnglish
}

public enum ChinesePolicy {
    public static func rank<S: StringProtocol>(run: S, context: RunContext, english: EnglishWords,
                                               layout: any KeyLayout = XiaoheLayout()) -> ChineseRank {
        // A capital starts English, even after pinyin keys (`nihcK`).
        guard !run.contains(where: \.isUppercase) else { return .none }
        let graph = layout.graph(for: run)
        guard graph.end > 0 else { return .none }
        if !graph.isComplete {
            // A stray key after pinyin (`woxianzaijiu` + `i`): like librime,
            // the keys that read convert and the rest stay as typed. Only for
            // whole spellings that can't be English, so `nginx` (`ng` as
            // initials) and `hanging` stay English.
            let plain = graph.edges.values.allSatisfy { $0.allSatisfy { $0.kind == .normal } }
            guard plain, !english.hasWord(withPrefix: run),
                  rank(run: run.prefix(graph.end), context: context, english: english, layout: layout) == .primary
            else { return .none }
            return .primary
        }
        switch context {
        case .afterEnglish:
            // Inside an English sentence Chinese is never offered: a run that
            // is no English word is a typo (`rela`), not 热辣.
            return .none
        case .afterChinese:
            return english.contains(run) ? .alternatives : .primary
        case .fresh:
            return english.hasWord(withPrefix: run) ? .alternatives : .primary
        }
    }

    /// The context for a run typed after `prefix` (what the composition holds
    /// before it). One English word inside Chinese text (`这个 bug 修好了`)
    /// keeps the Chinese going; two or more are an English sentence, even
    /// right after Chinese.
    public static func context<S: StringProtocol>(prefix: S, afterChineseCommit: Bool) -> RunContext {
        let words = prefix.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count
        if afterChineseCommit, words < 2 { return .afterChinese }
        return prefix.contains { !$0.isWhitespace } ? .afterEnglish : .fresh
    }

    /// The letters right before `cursor` in `text`, if the cursor is not in
    /// the middle of a word.
    public static func run(in text: String, cursor: Int) -> Substring {
        let end = text.index(text.startIndex, offsetBy: cursor)
        if end < text.endIndex, text[end].isASCII && text[end].isLetter { return "" }
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard text[previous].isASCII && text[previous].isLetter else { break }
            start = previous
        }
        return text[start..<end]
    }
}
