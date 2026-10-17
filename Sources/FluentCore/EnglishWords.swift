import Foundation

/// Lowercase English words (rime-ice's English dictionary, compiled by
/// `make dict`), for telling English apart from shuangpin keys.
public struct EnglishWords {
    private let words: [String]

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

    public func contains<S: StringProtocol>(_ word: S) -> Bool {
        let index = lowerBound(word)
        return index < words.count && words[index] == word
    }

    /// Whether some word starts with `prefix` (or is it).
    public func hasWord<S: StringProtocol>(withPrefix prefix: S) -> Bool {
        let index = lowerBound(prefix)
        return index < words.count && words[index].hasPrefix(prefix)
    }

    private func lowerBound<S: StringProtocol>(_ key: S) -> Int {
        var lo = 0, hi = words.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if words[mid] < key { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

/// Where Chinese candidates go for the letters typed at the caret. English
/// is the main language, so Chinese only goes first when the keys cannot be
/// (the start of) an English word.
public enum ChineseRank: Equatable {
    /// Not shuangpin (or typed with capitals): English only.
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
    /// only English words embedded in the Chinese text (`这个 bug 修好了`).
    case afterChinese
    /// English words typed earlier in this composition, not right after
    /// Chinese text: an English sentence.
    case afterEnglish
}

public enum ShuangpinPolicy {
    public static func rank<S: StringProtocol>(run: S, context: RunContext,
                                               english: EnglishWords) -> ChineseRank {
        guard Xiaohe.isValid(run) else { return .none }
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
