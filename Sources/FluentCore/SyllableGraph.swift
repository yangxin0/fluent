import Foundation

/// The ways a run of keys splits into syllables, like librime's syllable
/// graph: `edges[p]` are the syllables whose spelling starts at key `p`, and
/// every path from 0 to `end` is one reading of the keys.
public struct SyllableGraph: Equatable {
    public enum Kind: Int, Comparable {
        /// A whole spelling (or a fuzzy one, which only costs a penalty).
        case normal
        /// Initials only: `z` for any zh-/z- syllable.
        case abbreviation
        /// The start of a syllable the last keys have not finished.
        case completion

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Edge: Equatable {
        /// Key position right after the syllable.
        public var end: Int
        /// What the keys may stand for: one syllable, or several for an
        /// abbreviation, a completion or an ambiguous spelling.
        public var syllables: [SyllableID]
        /// Added to the weight of words that use it (librime's credibility).
        public var penalty: Float
        public var kind: Kind

        public init(end: Int, syllables: [SyllableID], penalty: Float = 0, kind: Kind = .normal) {
            self.end = end
            self.syllables = syllables
            self.penalty = penalty
            self.kind = kind
        }
    }

    public var edges: [Int: [Edge]]
    /// The farthest key position a path reaches.
    public var end: Int
    public var keyCount: Int

    public init(edges: [Int: [Edge]], end: Int, keyCount: Int) {
        self.edges = edges
        self.end = end
        self.keyCount = keyCount
    }

    /// Every key is part of some reading.
    public var isComplete: Bool { keyCount > 0 && end == keyCount }
}

/// How keys spell syllables: 小鹤双拼 or full pinyin.
public protocol KeyLayout {
    func graph<S: StringProtocol>(for keys: S) -> SyllableGraph
    /// The keys as shown inline, split into syllables (`ve ui`, `zhong guo`).
    func grouped<S: StringProtocol>(_ keys: S) -> String
}

extension KeyLayout {
    /// Whether the keys read as syllables all the way through.
    public func isValid<S: StringProtocol>(_ keys: S) -> Bool {
        !keys.isEmpty && graph(for: keys).isComplete
    }
}

/// 小鹤双拼: two keys per syllable, so the graph is a chain; a dangling last
/// key completes to every syllable it can start.
public struct XiaoheLayout: KeyLayout {
    /// librime's cost for completing a dangling last key (ln 0.05).
    static let completionPenalty: Float = -2.995_73

    public init() {}

    public func graph<S: StringProtocol>(for keys: S) -> SyllableGraph {
        let decoding = Xiaohe.decode(keys)
        var edges: [Int: [SyllableGraph.Edge]] = [:]
        for (index, slot) in decoding.slots.enumerated() {
            let start = 2 * index
            let partial = decoding.lastSlotIsPartial && index == decoding.slots.count - 1
            edges[start] = [partial
                ? SyllableGraph.Edge(end: start + 1, syllables: slot, penalty: Self.completionPenalty,
                                     kind: .completion)
                : SyllableGraph.Edge(end: start + 2, syllables: slot)]
        }
        return SyllableGraph(edges: edges, end: decoding.keyCount, keyCount: keys.count)
    }

    public func grouped<S: StringProtocol>(_ keys: S) -> String {
        Xiaohe.grouped(keys)
    }
}
