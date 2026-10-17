import Foundation

/// One conversion of (a prefix of) the typed keys.
public struct ChineseCandidate: Equatable {
    public var text: String
    /// Keys converted, counted from the start of the input. Fewer than typed
    /// means picking it leaves the rest of the keys to convert next.
    public var keyCount: Int
    /// The syllables it stands for.
    public var code: [SyllableID]
    /// Dimmed text shown after the candidate, e.g. a rare character's pinyin.
    public var comment: String?
    /// Ranking score (log probability, librime scale).
    public var weight: Float

    public init(text: String, keyCount: Int, code: [SyllableID], comment: String? = nil,
                weight: Float) {
        self.text = text
        self.keyCount = keyCount
        self.code = code
        self.comment = comment
        self.weight = weight
    }
}

/// Turns 小鹤双拼 keys into ranked Chinese candidates, following librime's
/// script translator: a whole-sentence candidate when no single word covers
/// the input, then words covering more of the input before shorter ones, and
/// within the same length by weight. Like the system shuangpin input method
/// it also offers a few longer words that start with the input (`ve ui` →
/// 这时候).
public final class XiaoheTranslator {
    public let lexicon: Lexicon

    /// librime's per-word cost when making a sentence (ln 1e-6): sentences
    /// prefer fewer, longer words.
    static let wordPenalty: Float = -13.815_51
    /// librime's cost for completing a dangling last key (ln 0.05).
    static let completionPenalty: Float = -2.995_73
    /// Cost for predicting syllables not typed yet (ln 0.3).
    static let predictionPenalty: Float = -1.203_97
    static let maxPredictions = 3
    static let maxPredictionScan = 4000
    static let maxWordsPerLength = 30
    static let maxCharacters = 120
    /// Single characters rarer than this get their pinyin as a comment.
    static let rareCharacterWeight = Lexicon.normalizedWeight(300)

    public init(lexicon: Lexicon) {
        self.lexicon = lexicon
    }

    public func candidates<S: StringProtocol>(for keys: S) -> [ChineseCandidate] {
        let decoding = Xiaohe.decode(keys)
        let slots = decoding.slots
        guard !slots.isEmpty else { return [] }

        // Words by the number of slots they cover, from the start.
        var bySlots = [[ChineseCandidate]](repeating: [], count: slots.count + 1)
        var predictions: [ChineseCandidate] = []
        walk(slots: slots, from: 0, decoding: decoding) { end, range, code, penalty in
            for index in lexicon.exactMatches(in: range) {
                bySlots[end].append(candidate(at: index, code: code, keyCount: decoding.keyCount(ofSlots: end),
                                              penalty: penalty))
            }
            if end == slots.count, end >= 2, !decoding.lastSlotIsPartial {
                predictions += predicted(in: range, typed: code, keyCount: decoding.keyCount)
            }
        }

        var result: [ChineseCandidate] = []
        if slots.count >= 2, bySlots[slots.count].isEmpty,
           let sentence = sentence(slots: slots, decoding: decoding) {
            result.append(sentence)
        }
        predictions.sort { $0.weight > $1.weight }
        var full = bySlots[slots.count] + predictions.prefix(Self.maxPredictions)
        full.sort { $0.weight > $1.weight }
        result += full.prefix(Self.maxWordsPerLength)
        for end in stride(from: slots.count - 1, through: 1, by: -1) {
            let words = bySlots[end].sorted { $0.weight > $1.weight }
            result += words.prefix(end == 1 ? Self.maxCharacters : Self.maxWordsPerLength)
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.text).inserted }
    }

    /// Visits every lexicon range reachable by spelling slots `start...` with
    /// one syllable per slot, passing the slot index the range ends at.
    private func walk(slots: [[SyllableID]], from start: Int, decoding: Xiaohe.Decoding,
                      visit: (_ end: Int, _ range: Lexicon.Range, _ code: [SyllableID],
                              _ penalty: Float) -> Void) {
        func step(_ range: Lexicon.Range, _ end: Int, _ code: [SyllableID]) {
            guard end < slots.count else { return }
            let partial = decoding.lastSlotIsPartial && end == slots.count - 1
            for syllable in slots[end] {
                guard let child = lexicon.child(of: range, syllable: syllable) else { continue }
                let code = code + [syllable]
                visit(end + 1, child, code, partial ? Self.completionPenalty : 0)
                step(child, end + 1, code)
            }
        }
        step(lexicon.root, start, [])
    }

    private func candidate(at index: Int, code: [SyllableID], keyCount: Int,
                           penalty: Float) -> ChineseCandidate {
        let weight = lexicon.weight(at: index)
        var comment: String?
        if code.count == 1, weight < Self.rareCharacterWeight {
            comment = Pinyin.syllables[Int(code[0])]
        }
        return ChineseCandidate(text: lexicon.text(at: index), keyCount: keyCount, code: code,
                                comment: comment, weight: weight + penalty)
    }

    /// The best few words up to two syllables longer than the input.
    private func predicted(in range: Lexicon.Range, typed: [SyllableID],
                           keyCount: Int) -> [ChineseCandidate] {
        var best: [ChineseCandidate] = []
        let exactEnd = lexicon.exactMatches(in: range).upperBound
        for index in exactEnd..<min(range.upper, exactEnd + Self.maxPredictionScan) {
            let length = lexicon.codeLength(at: index)
            guard length <= typed.count + 2 else { continue }
            let weight = lexicon.weight(at: index) + Self.predictionPenalty
            guard best.count < Self.maxPredictions || weight > best[best.count - 1].weight else { continue }
            best.append(ChineseCandidate(text: lexicon.text(at: index), keyCount: keyCount,
                                         code: lexicon.code(at: index), weight: weight))
            best.sort { $0.weight > $1.weight }
            if best.count > Self.maxPredictions { best.removeLast() }
        }
        return best
    }

    /// Dynamic programming over the word graph, like librime's Poet without
    /// a grammar model: maximize the summed word weights minus a per-word
    /// cost, never using a single word for the whole input.
    private func sentence(slots: [[SyllableID]], decoding: Xiaohe.Decoding) -> ChineseCandidate? {
        let count = slots.count
        // Best word for each (start, end) slot span.
        var edges = [[Int: ChineseCandidate]](repeating: [:], count: count)
        for start in 0..<count {
            walk(slots: slots, from: start, decoding: decoding) { end, range, code, penalty in
                guard let index = lexicon.exactMatches(in: range).first,
                      !(start == 0 && end == count) else { return }
                let word = candidate(at: index, code: code, keyCount: 0, penalty: penalty)
                if let existing = edges[start][end], existing.weight >= word.weight { return }
                edges[start][end] = word
            }
        }
        struct Line { var weight: Float; var words: [ChineseCandidate] }
        var best = [Line?](repeating: nil, count: count + 1)
        best[0] = Line(weight: 0, words: [])
        for start in 0..<count {
            guard let line = best[start] else { continue }
            for (end, word) in edges[start] {
                let weight = line.weight + word.weight + Self.wordPenalty
                if let existing = best[end], existing.weight >= weight { continue }
                best[end] = Line(weight: weight, words: line.words + [word])
            }
        }
        guard let line = best[count] else { return nil }
        return ChineseCandidate(text: line.words.map(\.text).joined(), keyCount: decoding.keyCount,
                                code: line.words.flatMap(\.code), weight: line.weight)
    }
}
