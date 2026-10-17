import Foundation

/// When to offer Chinese for the letters at the caret. What was typed is
/// always candidate 1, so offering Chinese never stands in the way of
/// English; only an English sentence (more than one word) gets none.
public enum ShuangpinPolicy {
    /// `afterEnglishWords`: the composition holds English words before the
    /// letters, and not right after Chinese text (`这个 bug 修好了` still
    /// offers Chinese after `bug`).
    public static func offersChinese<S: StringProtocol>(run: S, afterEnglishWords: Bool) -> Bool {
        !afterEnglishWords && Xiaohe.isValid(run)
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
