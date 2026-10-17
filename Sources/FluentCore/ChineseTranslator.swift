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

/// Turns keys into ranked Chinese candidates, following librime's script
/// translator: a whole-sentence candidate when no single word covers the
/// input, then words covering more of the input before shorter ones, and
/// within the same length by weight. Like the system shuangpin input method
/// it also offers a few longer words that start with the input (`ve ui` →
/// 这时候). Words learned in `userDictionary` come first among words of the
/// same length, as in librime. `layout` says how keys spell syllables.
public final class ChineseTranslator {
    public let lexicon: Lexicon
    public var userDictionary: UserDictionary?
    public var layout: any KeyLayout

    /// librime's per-word cost when making a sentence (ln 1e-6): sentences
    /// prefer fewer, longer words.
    static let wordPenalty: Float = -13.815_51
    /// Cost for predicting syllables not typed yet (ln 0.3).
    static let predictionPenalty: Float = -1.203_97
    static let maxPredictions = 3
    static let maxPredictionScan = 4000
    static let maxWordsPerLength = 30
    static let maxCharacters = 120
    /// Single characters rarer than this get their pinyin as a comment.
    static let rareCharacterWeight = Lexicon.normalizedWeight(300)

    public init(lexicon: Lexicon, userDictionary: UserDictionary? = nil, layout: any KeyLayout = XiaoheLayout()) {
        self.lexicon = lexicon
        self.userDictionary = userDictionary
        self.layout = layout
    }

    public func candidates<S: StringProtocol>(for keys: S) -> [ChineseCandidate] {
        let graph = layout.graph(for: keys)
        guard graph.end > 0 else { return [] }

        // Words by the key position they end at, from the start.
        var byEnd: [Int: [ChineseCandidate]] = [:]
        var learnedByEnd: [Int: [ChineseCandidate]] = [:]
        var predictions: [ChineseCandidate] = []
        walk(graph, from: 0) { end, range, code, penalty, plain in
            for index in lexicon.exactMatches(in: range) {
                byEnd[end, default: []].append(candidate(at: index, code: code, keyCount: end, penalty: penalty))
            }
            if end == graph.end, code.count >= 2, plain {
                predictions += predicted(in: range, typed: code, keyCount: end)
            }
        }
        walkLearned(graph, from: 0) { end, code, penalty in
            for word in userDictionary!.words(for: code) {
                learnedByEnd[end, default: []].append(
                    ChineseCandidate(text: word.text, keyCount: end, code: code, weight: word.weight + penalty))
            }
        }

        var result: [ChineseCandidate] = []
        if byEnd[graph.end] == nil, learnedByEnd[graph.end] == nil, let sentence = sentence(graph) {
            result.append(sentence)
        }
        predictions.sort { $0.weight > $1.weight }
        byEnd[graph.end, default: []] += predictions.prefix(Self.maxPredictions)
        for end in Set(byEnd.keys).union(learnedByEnd.keys).sorted(by: >) {
            result += (learnedByEnd[end] ?? []).sorted { $0.weight > $1.weight }
            let words = (byEnd[end] ?? []).sorted { $0.weight > $1.weight }
            // Plenty of single characters, fewer words of each length, still
            // by weight (full pinyin mixes both: `xian` is 先 and 西安).
            result += (words.filter { $0.code.count > 1 }.prefix(Self.maxWordsPerLength)
                + words.filter { $0.code.count == 1 }.prefix(Self.maxCharacters))
                .sorted { $0.weight > $1.weight }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.text).inserted }
    }

    /// Like `walk`, over the learned words: visits every code spelled from
    /// key `start` that is a learned word or the start of one.
    private func walkLearned(_ graph: SyllableGraph, from start: Int,
                             visit: (_ end: Int, _ code: [SyllableID], _ penalty: Float) -> Void) {
        guard let user = userDictionary, user.count > 0 else { return }
        func step(_ position: Int, _ code: [SyllableID], _ penalty: Float) {
            for edge in graph.edges[position] ?? [] {
                for syllable in edge.syllables {
                    let code = code + [syllable]
                    guard user.hasPrefix(code) else { continue }
                    visit(edge.end, code, penalty + edge.penalty)
                    step(edge.end, code, penalty + edge.penalty)
                }
            }
        }
        step(start, [], 0)
    }

    /// Visits every lexicon range reachable by following the graph from key
    /// `start`, one syllable per edge, with the key position it ends at and
    /// whether every edge on the way was a whole spelling (`plain`).
    private func walk(_ graph: SyllableGraph, from start: Int,
                      visit: (_ end: Int, _ range: Lexicon.Range, _ code: [SyllableID], _ penalty: Float,
                              _ plain: Bool) -> Void) {
        func step(_ range: Lexicon.Range, _ position: Int, _ code: [SyllableID], _ penalty: Float, _ plain: Bool) {
            for edge in graph.edges[position] ?? [] {
                let plain = plain && edge.kind == .normal
                for syllable in edge.syllables {
                    guard let child = lexicon.child(of: range, syllable: syllable) else { continue }
                    let code = code + [syllable]
                    visit(edge.end, child, code, penalty + edge.penalty, plain)
                    step(child, edge.end, code, penalty + edge.penalty, plain)
                }
            }
        }
        step(lexicon.root, start, [], 0, true)
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
    private func sentence(_ graph: SyllableGraph) -> ChineseCandidate? {
        // Best word for each (start, end) key span.
        var words: [Int: [Int: ChineseCandidate]] = [:]
        func offer(_ word: ChineseCandidate, from start: Int, to end: Int) {
            guard !(start == 0 && end == graph.end) else { return }
            if let existing = words[start]?[end], existing.weight >= word.weight { return }
            words[start, default: [:]][end] = word
        }
        for start in graph.edges.keys {
            walk(graph, from: start) { end, range, code, penalty, _ in
                guard let index = lexicon.exactMatches(in: range).first else { return }
                offer(candidate(at: index, code: code, keyCount: 0, penalty: penalty), from: start, to: end)
            }
            walkLearned(graph, from: start) { end, code, penalty in
                guard let word = userDictionary!.words(for: code).first else { return }
                offer(ChineseCandidate(text: word.text, keyCount: 0, code: code, weight: word.weight + penalty),
                      from: start, to: end)
            }
        }
        struct Line { var weight: Float; var words: [ChineseCandidate] }
        var best: [Int: Line] = [0: Line(weight: 0, words: [])]
        for start in words.keys.sorted() {
            guard let line = best[start] else { continue }
            for (end, word) in words[start]! {
                let weight = line.weight + word.weight + Self.wordPenalty
                if let existing = best[end], existing.weight >= weight { continue }
                best[end] = Line(weight: weight, words: line.words + [word])
            }
        }
        guard let line = best[graph.end] else { return nil }
        return ChineseCandidate(text: line.words.map(\.text).joined(), keyCount: graph.end,
                                code: line.words.flatMap(\.code), weight: line.weight)
    }
}
