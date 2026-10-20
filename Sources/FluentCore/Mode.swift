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

    /// Its key in the config's `prompts` and in docs/default-prompts.json.
    public var promptKey: String {
        switch self {
        case .fix: return "fix"
        case .polish: return "polish"
        case .interpret: return "translate"
        }
    }

    /// Follows every prompt, the built-in ones and the user's own, so that
    /// whatever the model replies can be inserted as is.
    public static let outputRule =
        "Output ONLY the resulting text. No quotes, no explanations. Preserve the author's meaning."

    /// The built-in prompt, which the config's `prompts` may replace. The
    /// Settings app has the same text (docs/default-prompts.json).
    public var defaultPrompt: String {
        switch self {
        case .fix:
            return "You correct English text. Fix grammar, spelling, and punctuation only. "
                + "Change nothing else; keep the author's wording and tone. "
                + "If the text is already correct, return it unchanged."
        case .polish:
            return "You improve English text. Rewrite it as a fluent native English speaker would: "
                + "natural word choice, idiomatic phrasing, same meaning and register."
        case .interpret:
            return "You turn rough input into clear English. The input may be fragmentary, ungrammatical, "
                + "or mix Chinese and English. Infer the intended message and write it as clear, natural English."
        }
    }

    /// System instructions sent to the model: `prompt` (the built-in one
    /// when it is nil or blank), a blank line, then the output rule.
    public func instructions(prompt: String? = nil) -> String {
        let own = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (own.isEmpty ? defaultPrompt : own) + "\n\n" + Mode.outputRule
    }
}
