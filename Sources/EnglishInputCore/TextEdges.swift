import Foundation

/// The model returns trimmed text, but the whitespace the user typed at the
/// edges of a composition is meaningful: a leading space separates the new
/// sentence from the one already committed, a trailing space or newline
/// sets up the next one. Restore it around the improved text.
public enum TextEdges {
    public static func leadingWhitespace(of s: String) -> Substring {
        s.prefix { $0.isWhitespace }
    }

    public static func trailingWhitespace(of s: String) -> Substring {
        guard let lastNonSpace = s.lastIndex(where: { !$0.isWhitespace }) else { return s[...] }
        return s[s.index(after: lastNonSpace)...]
    }

    /// `improved` with `raw`'s leading and trailing whitespace re-applied.
    /// If the improvement is blank it is returned unchanged.
    public static func restoringEdges(of raw: String, to improved: String) -> String {
        let core = improved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return improved }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return improved }
        return leadingWhitespace(of: raw) + core + trailingWhitespace(of: raw)
    }
}
