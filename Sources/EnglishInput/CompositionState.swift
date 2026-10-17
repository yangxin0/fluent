import Foundation
import EnglishInputCore

struct CompositionState {
    enum Status {
        case idle
        case improving
        case done
        case failed(String)
    }

    var raw: String = ""
    /// Cursor position in characters (raw is typed text, so characters ≈ scalars).
    var cursor: Int = 0
    var improved: String = ""
    var status: Status = .idle
    /// Once the marked text nears the window edge in a terminal, the panel
    /// keeps showing the typed text for the rest of this composition.
    var showTypedInPanel = false
    /// Terminal edge detection state, fed once per keystroke.
    var edgeTracker = EdgeTracker()
    /// Character count at the last edge check, to skip redundant checks.
    var edgeCheckedCount = -1

    /// Set while composing Chinese (小鹤双拼 keys that cannot be English);
    /// `raw` is then empty and `chinesePrefix` holds the whitespace typed
    /// before the keys, which is committed with the Chinese text.
    var chinese: ShuangpinComposer?
    var chinesePrefix = ""
    /// Chinese readings of the letters at the caret when they are also (the
    /// start of) English: number keys 2… pick them once they are visible.
    var alternatives: [ChineseCandidate] = []
    var alternativesVisible = false

    var isComposing: Bool { !raw.isEmpty || chinese != nil }

    /// Improved text is only committable once the stream finished. The
    /// whitespace typed at the edges (e.g. the space that separates this
    /// sentence from the previous one) is kept even though the model
    /// returns trimmed text.
    var committableImproved: String? {
        if case .done = status, !improved.isEmpty {
            return TextEdges.restoringEdges(of: raw, to: improved)
        }
        return nil
    }

    /// UTF-16 offset of the cursor, for setMarkedText's selectionRange.
    var cursorUTF16Offset: Int {
        let idx = raw.index(raw.startIndex, offsetBy: cursor)
        return raw.utf16.distance(from: raw.utf16.startIndex, to: idx)
    }

    mutating func insert(_ text: String) {
        let idx = raw.index(raw.startIndex, offsetBy: cursor)
        raw.insert(contentsOf: text, at: idx)
        cursor += text.count
    }

    mutating func backspace() {
        guard cursor > 0 else { return }
        let idx = raw.index(raw.startIndex, offsetBy: cursor - 1)
        raw.remove(at: idx)
        cursor -= 1
    }

    mutating func moveLeft() { cursor = max(0, cursor - 1) }
    mutating func moveRight() { cursor = min(raw.count, cursor + 1) }

    mutating func reset() {
        self = CompositionState()
    }
}
