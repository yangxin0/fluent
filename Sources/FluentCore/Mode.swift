import Foundation

/// The three improvement modes. These are internal behavior of the single
/// input source, switched from the IME menu or Ctrl+Tab — not TSM input modes.
public enum Mode: String, CaseIterable, Codable {
    case fix
    case polish
    case interpret

    public var displayName: String {
        switch self {
        case .fix: return "Fix — grammar & spelling only"
        case .polish: return "Polish — native-speaker rephrase"
        case .interpret: return "Translate — rough/mixed input to English"
        }
    }

    /// One-letter badge at the start of the candidate bar (Chinese shows 双).
    public var badge: String {
        switch self {
        case .fix: return "F"
        case .polish: return "P"
        case .interpret: return "T"
        }
    }

    public var next: Mode {
        let all = Mode.allCases
        let idx = all.firstIndex(of: self)!
        return all[(idx + 1) % all.count]
    }

    private static let outputRule =
        "Output ONLY the resulting text. No quotes, no explanations. Preserve the author's meaning."

    /// System instructions sent to the model for this mode.
    public var instructions: String {
        switch self {
        case .fix:
            return "You correct English text. Fix grammar, spelling, and punctuation only. "
                + "Change nothing else; keep the author's wording and tone. "
                + "If the text is already correct, return it unchanged. "
                + Mode.outputRule
        case .polish:
            return "You improve English text. Rewrite it as a fluent native English speaker would: "
                + "natural word choice, idiomatic phrasing, same meaning and register. "
                + Mode.outputRule
        case .interpret:
            return "You turn rough input into clear English. The input may be fragmentary, ungrammatical, "
                + "or mix Chinese and English. Infer the intended message and write it as clear, natural English. "
                + Mode.outputRule
        }
    }
}
