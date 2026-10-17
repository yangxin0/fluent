import Foundation

/// One Chinese composition in progress: the typed keys, the words already
/// picked for a leading part of them, and the candidates for the rest.
///
/// Picking a candidate that converts only some of the remaining keys keeps
/// composing with what is left (librime's partial selection); Backspace right
/// after such a pick takes it back.
public struct ChineseComposer {
    public struct Segment: Equatable {
        public var text: String
        public var keyCount: Int
        public var code: [SyllableID]
    }

    public private(set) var keys: String
    public private(set) var segments: [Segment] = []
    public private(set) var candidates: [ChineseCandidate] = []
    /// Index into `candidates`.
    public private(set) var highlighted = 0
    public let pageSize: Int
    private let translator: ChineseTranslator
    private var lastEditWasSelection = false

    public init(keys: String, translator: ChineseTranslator, pageSize: Int = 6) {
        self.keys = keys
        self.translator = translator
        self.pageSize = pageSize
        translate()
    }

    public var confirmedKeyCount: Int { segments.reduce(0) { $0 + $1.keyCount } }
    public var confirmedText: String { segments.map(\.text).joined() }
    public var remainingKeys: Substring { keys.dropFirst(confirmedKeyCount) }

    public var page: Int { highlighted / pageSize }
    public var pageCount: Int { (candidates.count + pageSize - 1) / pageSize }
    public var pageCandidates: ArraySlice<ChineseCandidate> {
        let start = page * pageSize
        return candidates[start..<min(start + pageSize, candidates.count)]
    }
    public var highlightedOnPage: Int { highlighted - page * pageSize }

    /// The candidates shown when the bar is expanded into a grid of `rows`
    /// pages, one per row. It starts at a multiple of `rows` pages so the
    /// grid stays put while the highlight moves inside it.
    public func gridRange(rows: Int) -> Range<Int> {
        let span = pageSize * max(rows, 1)
        let start = highlighted / span * span
        return start..<min(start + span, candidates.count)
    }

    /// What to learn once `select` returns the committed text: the picked
    /// words (keys offered as typed are skipped by the dictionary).
    public var pickedWords: [(text: String, code: [SyllableID])] {
        segments.map { ($0.text, $0.code) }
    }

    /// What to learn when punctuation commits `highlightedText`: the picked
    /// words and the highlighted candidate.
    public var highlightedWords: [(text: String, code: [SyllableID])] {
        guard highlighted < candidates.count else { return pickedWords }
        let candidate = candidates[highlighted]
        return pickedWords + [(candidate.text, candidate.code)]
    }

    /// Inline text: the converted words, then the remaining keys grouped per
    /// syllable (`这是 ge`).
    public var preedit: (converted: String, raw: String) {
        (confirmedText, translator.layout.grouped(remainingKeys))
    }

    /// What to insert if the composition is cut short (focus loss, a
    /// shortcut): what is shown, without the grouping spaces.
    public var interruptedText: String { confirmedText + remainingKeys }

    /// What to insert when punctuation ends the composition: the converted
    /// words, the highlighted candidate, and any keys it leaves unconverted.
    public var highlightedText: String {
        guard highlighted < candidates.count else { return interruptedText }
        let candidate = candidates[highlighted]
        return confirmedText + candidate.text + remainingKeys.dropFirst(candidate.keyCount)
    }

    public mutating func append(_ key: Character) {
        keys.append(key)
        lastEditWasSelection = false
        translate()
    }

    /// Takes back the last pick if nothing was typed since, else deletes the
    /// last key. Returns false once nothing is left to compose.
    public mutating func backspace() -> Bool {
        if lastEditWasSelection, !segments.isEmpty {
            segments.removeLast()
        } else {
            guard !keys.isEmpty else { return false }
            keys.removeLast()
            lastEditWasSelection = false
            // Deleting into a picked word reopens it.
            if keys.count == confirmedKeyCount, !segments.isEmpty {
                segments.removeLast()
            }
        }
        guard !keys.isEmpty else { return false }
        translate()
        return true
    }

    /// Picks `candidates[index]`. Returns the text to commit once every key
    /// is converted, nil while keys remain (or for an invalid index).
    public mutating func select(_ index: Int) -> String? {
        guard index >= 0, index < candidates.count else { return nil }
        let candidate = candidates[index]
        segments.append(Segment(text: candidate.text, keyCount: candidate.keyCount, code: candidate.code))
        if confirmedKeyCount >= keys.count {
            return confirmedText
        }
        lastEditWasSelection = true
        translate()
        return nil
    }

    /// Picks the `index`-th candidate (0-based) on the current page.
    public mutating func selectOnPage(_ index: Int) -> String? {
        guard index >= 0, index < pageCandidates.count else { return nil }
        return select(page * pageSize + index)
    }

    public mutating func moveHighlight(by delta: Int) {
        guard !candidates.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), candidates.count - 1)
    }

    public mutating func turnPage(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let target = min(max(page + delta, 0), pageCount - 1)
        highlighted = target * pageSize
    }

    private mutating func translate() {
        let remaining = remainingKeys
        candidates = translator.candidates(for: remaining)
        if candidates.isEmpty {
            // Not shuangpin from the start: offer the keys as typed.
            candidates = [ChineseCandidate(text: String(remaining), keyCount: remaining.count,
                                           code: [], weight: -.infinity)]
        }
        highlighted = 0
    }
}
