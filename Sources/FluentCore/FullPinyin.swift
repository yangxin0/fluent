import Foundation

/// Full pinyin (全拼). Syllables have any length, so keys can split several
/// ways (`xian` → xian or xi an); this builds librime's syllable graph:
///
/// - every syllable spelled from a key a path reaches is an edge;
/// - with `abbreviations`, a syllable's initial alone also spells it (`zg` →
///   zhong guo, `zh` for any zh- syllable), at a cost, as in librime's
///   `abbrev` rules;
/// - `fuzzy` pairs (`zh=z`, `an=ang`) add spellings at a cost;
/// - keys left unfinished at the end complete to every syllable they start
///   (`zhon` → zhong);
/// - `'` separates syllables (`xi'an`);
/// - edges worse than the best way to cover the keys are pruned, so
///   abbreviations drop out wherever whole spellings fit.
public struct FullPinyinLayout: KeyLayout {
    typealias Kind = SyllableGraph.Kind

    /// librime's credibility for abbreviated and fuzzy spellings (ln 0.5).
    static let abbreviationPenalty: Float = -0.693_15
    static let fuzzyPenalty: Float = -0.693_15
    /// librime's cost for completing an unfinished syllable (ln 0.05).
    static let completionPenalty: Float = -2.995_73
    static let maxSpellingLength = 6
    static let delimiter = UInt8(ascii: "'")

    struct Reading: Equatable {
        var syllable: SyllableID
        var penalty: Float
        var kind: Kind
    }

    public let abbreviations: Bool
    public let fuzzy: [String]
    private let spellings: [String: [Reading]]
    /// Proper prefixes of whole spellings, for completing the last keys.
    private let completions: [String: [SyllableID]]

    /// `fuzzy` lists pairs to treat as the same, like `"zh=z"` or `"an=ang"`;
    /// unknown entries are ignored.
    public init(abbreviations: Bool = true, fuzzy: [String] = []) {
        self.abbreviations = abbreviations
        self.fuzzy = fuzzy
        let pairs = fuzzy.compactMap(Self.pair)
        var spellings: [String: [Reading]] = [:]
        var completions: [String: [SyllableID]] = [:]
        func add(_ spelling: String, _ reading: Reading) {
            var readings = spellings[spelling, default: []]
            if let index = readings.firstIndex(where: { $0.syllable == reading.syllable }) {
                // Keep the cheapest way to spell a syllable.
                if (reading.kind, -reading.penalty) < (readings[index].kind, -readings[index].penalty) {
                    readings[index] = reading
                }
            } else {
                readings.append(reading)
            }
            spellings[spelling] = readings
        }
        func addWhole(_ spelling: String, _ id: SyllableID, penalty: Float) {
            add(spelling, Reading(syllable: id, penalty: penalty, kind: .normal))
            for length in 1..<spelling.count {
                let prefix = String(spelling.prefix(length))
                if !(completions[prefix]?.contains(id) ?? false) { completions[prefix, default: []].append(id) }
            }
        }
        for (index, syllable) in Pinyin.syllables.enumerated() {
            let id = SyllableID(index)
            addWhole(syllable, id, penalty: 0)
            // rime-ice spells ü as v; people also type lue / nue.
            if syllable == "lve" || syllable == "nve" {
                addWhole(String(syllable.first!) + "ue", id, penalty: 0)
            }
            for (a, b) in pairs {
                for variant in Self.variants(of: syllable, swapping: a, b) {
                    addWhole(variant, id, penalty: Self.fuzzyPenalty)
                }
            }
            if abbreviations {
                let initial = Reading(syllable: id, penalty: Self.abbreviationPenalty, kind: .abbreviation)
                add(String(syllable.prefix(1)), initial)
                if ["zh", "ch", "sh"].contains(String(syllable.prefix(2))) {
                    add(String(syllable.prefix(2)), initial)
                }
            }
        }
        self.spellings = spellings
        self.completions = completions
    }

    /// `"zh=z"` → ("zh", "z"); either order works.
    private static func pair(_ rule: String) -> (String, String)? {
        let parts = rule.lowercased().split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty, parts[0] != parts[1],
              parts.allSatisfy({ $0.allSatisfy { $0 >= "a" && $0 <= "z" } })
        else { return nil }
        return (parts[0], parts[1])
    }

    private static let initials: Set<String> = [
        "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
        "zh", "ch", "sh", "r", "z", "c", "s", "y", "w",
    ]

    /// The other spellings of `syllable` when `a` and `b` are the same: the
    /// initial swapped for an initial pair (zh/z, n/l), else the final
    /// (an/ang, in/ing).
    private static func variants(of syllable: String, swapping a: String, _ b: String) -> [String] {
        // Longer first, so `zh` is not read as `z` + `h…`.
        let (long, short) = a.count >= b.count ? (a, b) : (b, a)
        if initials.contains(a) && initials.contains(b) {
            if syllable.hasPrefix(long) { return [short + syllable.dropFirst(long.count)] }
            if syllable.hasPrefix(short) && !(long.hasPrefix(short) && syllable.hasPrefix(long)) {
                return [long + syllable.dropFirst(short.count)]
            }
            return []
        }
        if syllable.hasSuffix(long) { return [syllable.dropLast(long.count) + short] }
        if syllable.hasSuffix(short) && !(long.hasSuffix(short) && syllable.hasSuffix(long)) {
            return [syllable.dropLast(short.count) + long]
        }
        return []
    }

    public func graph<S: StringProtocol>(for keys: S) -> SyllableGraph {
        let bytes = Array(keys.utf8)
        let count = bytes.count
        var edges: [Int: [SyllableGraph.Edge]] = [:]
        var reachable = [Bool](repeating: false, count: count + 1)
        reachable[0] = true
        // A syllable's end absorbs the separators after it.
        func afterDelimiters(_ position: Int) -> Int {
            var position = position
            while position < count && bytes[position] == Self.delimiter { position += 1 }
            return position
        }

        for vertex in 0..<count where reachable[vertex] {
            let start = afterDelimiters(vertex)
            guard start < count else {
                reachable[count] = true
                continue
            }
            for length in 1...min(Self.maxSpellingLength, count - start) {
                let spelling = String(decoding: bytes[start..<start + length], as: UTF8.self)
                guard let readings = spellings[spelling] else { continue }
                let end = afterDelimiters(start + length)
                // One edge per kind and cost, holding all its syllables.
                var groups: [(Kind, Float, [SyllableID])] = []
                for reading in readings {
                    if let index = groups.firstIndex(where: { $0.0 == reading.kind && $0.1 == reading.penalty }) {
                        groups[index].2.append(reading.syllable)
                    } else {
                        groups.append((reading.kind, reading.penalty, [reading.syllable]))
                    }
                }
                for (kind, penalty, ids) in groups {
                    edges[vertex, default: []].append(
                        SyllableGraph.Edge(end: end, syllables: ids, penalty: penalty, kind: kind))
                }
                reachable[end] = true
            }
        }

        var farthest = reachable.lastIndex(of: true) ?? 0
        if farthest < count {
            // The last keys may be a syllable still being typed.
            let start = afterDelimiters(farthest)
            let rest = String(decoding: bytes[start..<count], as: UTF8.self)
            if !rest.contains("'"), let ids = completions[rest] {
                edges[farthest, default: []].append(SyllableGraph.Edge(
                    end: count, syllables: ids, penalty: Self.completionPenalty, kind: .completion))
                farthest = count
            }
        }
        return SyllableGraph(edges: Self.pruned(edges, to: farthest, keyCount: count), end: farthest,
                             keyCount: count)
    }

    /// Keeps the edges on paths from 0 to `end` that are no worse than the
    /// best path's kind (a path is as bad as its worst edge).
    private static func pruned(_ edges: [Int: [SyllableGraph.Edge]], to end: Int,
                               keyCount: Int) -> [Int: [SyllableGraph.Edge]] {
        var best = [Kind?](repeating: nil, count: keyCount + 1)
        best[0] = .normal
        for vertex in 0...keyCount {
            guard let kind = best[vertex] else { continue }
            for edge in edges[vertex] ?? [] {
                let pathKind = max(kind, edge.kind)
                if best[edge.end].map({ pathKind < $0 }) ?? true { best[edge.end] = pathKind }
            }
        }
        let target = best[end] ?? .normal
        var kept = edges.mapValues { $0.filter { $0.kind <= target } }

        var fromStart = [Bool](repeating: false, count: keyCount + 1)
        fromStart[0] = true
        for vertex in 0...keyCount where fromStart[vertex] {
            for edge in kept[vertex] ?? [] { fromStart[edge.end] = true }
        }
        var toEnd = [Bool](repeating: false, count: keyCount + 1)
        toEnd[end] = true
        for vertex in stride(from: keyCount, through: 0, by: -1) where vertex != end {
            toEnd[vertex] = (kept[vertex] ?? []).contains { toEnd[$0.end] }
        }
        for (vertex, list) in kept {
            let onPath = fromStart[vertex] ? list.filter { toEnd[$0.end] && $0.end <= end } : []
            kept[vertex] = onPath.isEmpty ? nil : onPath
        }
        return kept
    }

    /// The keys split along the best reading: the fewest syllables among the
    /// best kind of path (`xian`, not `xi an`), keeping typed separators.
    public func grouped<S: StringProtocol>(_ keys: S) -> String {
        let graph = graph(for: keys)
        let text = Array(keys)
        var best: [Int: (kind: Kind, count: Int, previous: Int)] = [0: (.normal, 0, -1)]
        for vertex in graph.edges.keys.sorted() {
            guard let path = best[vertex] else { continue }
            for edge in graph.edges[vertex]! {
                let candidate = (kind: max(path.kind, edge.kind), count: path.count + 1, previous: vertex)
                if let existing = best[edge.end],
                   (existing.kind, existing.count) <= (candidate.kind, candidate.count) { continue }
                best[edge.end] = candidate
            }
        }
        var segments: [String] = []
        var position = graph.end
        while position > 0, let path = best[position] {
            segments.insert(String(text[path.previous..<position]), at: 0)
            position = path.previous
        }
        if graph.end < text.count { segments.append(String(text[graph.end...])) }
        var result = ""
        for segment in segments {
            if !result.isEmpty && !result.hasSuffix("'") { result += " " }
            result += segment
        }
        return result
    }
}
