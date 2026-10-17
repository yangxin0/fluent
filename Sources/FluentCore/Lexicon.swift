import Foundation

/// Chinese words keyed by syllable sequences, compiled from rime-ice by
/// `fluent-dict` (`make dict`).
///
/// Entries are sorted by code (syllable ids, shorter first on a shared
/// prefix) and then by weight, highest first. All entries sharing a code
/// prefix are therefore contiguous, so the sorted array works as a trie:
/// `child(of:depth:syllable:)` narrows a range by one syllable, and the
/// entries whose code ends exactly at that depth lead each range.
///
/// File layout (little endian, as on all Apple hardware): magic `XHLX`, version, `Pinyin.tableHash`,
/// entry count, code-pool length, text-pool length; then per-entry arrays
/// (code start u32, code length u8, text start u32, text length u8,
/// weight f32) followed by the code pool (u16 syllable ids) and the text pool
/// (UTF-8).
public final class Lexicon {
    public struct Entry: Equatable {
        public var text: String
        public var code: [SyllableID]
        /// Natural log of the rime-ice weight, normalized like librime:
        /// `ln(weight) - ln(1e8)`.
        public var weight: Float

        public init(text: String, code: [SyllableID], weight: Float) {
            self.text = text
            self.code = code
            self.weight = weight
        }
    }

    /// Entries sharing a code prefix of length `depth`.
    public struct Range: Equatable {
        public var lower: Int
        public var upper: Int
        public var depth: Int
        public var isEmpty: Bool { lower >= upper }
    }

    static let magic: [UInt8] = Array("XHLX".utf8)
    static let version: UInt32 = 1

    private let codeStart: [UInt32]
    private let codeLength: [UInt8]
    private let textStart: [UInt32]
    private let textLength: [UInt8]
    private let weights: [Float]
    private let codePool: [UInt16]
    private let textPool: [UInt8]

    public var count: Int { weights.count }
    public var root: Range { Range(lower: 0, upper: count, depth: 0) }

    public enum LoadError: Error, Equatable {
        case badHeader
        case staleSyllableTable
        case truncated
    }

    /// Builds an in-memory lexicon (used by tests and the dictionary tool).
    public convenience init(entries: [Entry]) {
        try! self.init(data: Lexicon.encode(entries))
    }

    public convenience init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        var reader = Reader(data: data)
        guard try reader.bytes(4) == Lexicon.magic, try reader.scalar(UInt32.self) == Lexicon.version
        else { throw LoadError.badHeader }
        guard try reader.scalar(UInt32.self) == Pinyin.tableHash else {
            throw LoadError.staleSyllableTable
        }
        let entries = Int(try reader.scalar(UInt32.self))
        let codes = Int(try reader.scalar(UInt32.self))
        let textBytes = Int(try reader.scalar(UInt32.self))
        codeStart = try reader.array(UInt32.self, count: entries)
        codeLength = try reader.array(UInt8.self, count: entries)
        textStart = try reader.array(UInt32.self, count: entries)
        textLength = try reader.array(UInt8.self, count: entries)
        weights = try reader.array(Float.self, count: entries)
        codePool = try reader.array(UInt16.self, count: codes)
        textPool = try reader.array(UInt8.self, count: textBytes)
    }

    // MARK: - Entry access

    public func text(at index: Int) -> String {
        let start = Int(textStart[index])
        return String(decoding: textPool[start..<start + Int(textLength[index])], as: UTF8.self)
    }

    public func weight(at index: Int) -> Float { weights[index] }

    public func codeLength(at index: Int) -> Int { Int(codeLength[index]) }

    public func code(at index: Int) -> [SyllableID] {
        let start = Int(codeStart[index])
        return Array(codePool[start..<start + Int(codeLength[index])])
    }

    public func entry(at index: Int) -> Entry {
        Entry(text: text(at: index), code: code(at: index), weight: weights[index])
    }

    private func syllable(at index: Int, position: Int) -> SyllableID {
        codePool[Int(codeStart[index]) + position]
    }

    // MARK: - Trie navigation

    /// Entries in `range` whose code is exactly `range.depth` long; they lead
    /// the range, highest weight first.
    public func exactMatches(in range: Range) -> Swift.Range<Int> {
        range.lower..<firstLonger(in: range)
    }

    /// The sub-range whose next syllable is `syllable`, or nil if none.
    public func child(of range: Range, syllable: SyllableID) -> Range? {
        let depth = range.depth
        // Past the exact matches, entries are sorted by their syllable at
        // `depth`: binary-search the run equal to `syllable`.
        var lo = firstLonger(in: range), hi = range.upper
        while lo < hi {
            let mid = (lo + hi) / 2
            if self.syllable(at: mid, position: depth) < syllable { lo = mid + 1 } else { hi = mid }
        }
        let lower = lo
        hi = range.upper
        while lo < hi {
            let mid = (lo + hi) / 2
            if self.syllable(at: mid, position: depth) <= syllable { lo = mid + 1 } else { hi = mid }
        }
        guard lower < lo else { return nil }
        return Range(lower: lower, upper: lo, depth: depth + 1)
    }

    /// The range for an exact code prefix, or nil if no entry starts with it.
    public func range(forPrefix code: [SyllableID]) -> Range? {
        var range = root
        for syllable in code {
            guard let next = child(of: range, syllable: syllable) else { return nil }
            range = next
        }
        return range
    }

    private func firstLonger(in range: Range) -> Int {
        var lo = range.lower, hi = range.upper
        while lo < hi {
            let mid = (lo + hi) / 2
            if Int(codeLength[mid]) <= range.depth { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: - Encoding

    /// Weight as stored: librime's log-probability normalization.
    public static func normalizedWeight(_ raw: Double) -> Float {
        Float(log(max(raw, 1)) - log(1e8))
    }

    /// Sorts the entries into lexicon order and serializes them.
    public static func encode(_ entries: [Entry]) -> Data {
        let sorted = entries.sorted { a, b in
            if a.code != b.code { return a.code.lexicographicallyPrecedes(b.code) }
            return a.weight > b.weight
        }
        var codePool: [UInt16] = []
        var textPool: [UInt8] = []
        var codeStart: [UInt32] = [], codeLength: [UInt8] = []
        var textStart: [UInt32] = [], textLength: [UInt8] = []
        var weights: [Float] = []
        for entry in sorted {
            let text = Array(entry.text.utf8)
            precondition(text.count <= Int(UInt8.max) && entry.code.count <= Int(UInt8.max)
                         && !entry.code.isEmpty)
            codeStart.append(UInt32(codePool.count))
            codeLength.append(UInt8(entry.code.count))
            codePool.append(contentsOf: entry.code)
            textStart.append(UInt32(textPool.count))
            textLength.append(UInt8(text.count))
            textPool.append(contentsOf: text)
            weights.append(entry.weight)
        }
        var data = Data(magic)
        for value in [version, Pinyin.tableHash, UInt32(sorted.count),
                      UInt32(codePool.count), UInt32(textPool.count)] {
            append(value, to: &data)
        }
        appendArray(codeStart, to: &data)
        appendArray(codeLength, to: &data)
        appendArray(textStart, to: &data)
        appendArray(textLength, to: &data)
        appendArray(weights, to: &data)
        appendArray(codePool, to: &data)
        appendArray(textPool, to: &data)
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendArray<T>(_ array: [T], to data: inout Data) {
        array.withUnsafeBytes { data.append(contentsOf: $0) }
    }

    /// Sequential little-endian reader that copies each section into an
    /// array, so lookups never touch unaligned memory.
    private struct Reader {
        let data: Data
        var offset: Int

        init(data: Data) {
            self.data = data
            offset = data.startIndex
        }

        mutating func bytes(_ count: Int) throws -> [UInt8] {
            try array(UInt8.self, count: count)
        }

        mutating func scalar<T: FixedWidthInteger>(_: T.Type) throws -> T {
            T(littleEndian: try array(T.self, count: 1)[0])
        }

        mutating func array<T>(_: T.Type, count: Int) throws -> [T] {
            let byteCount = count * MemoryLayout<T>.stride
            guard count >= 0, offset + byteCount <= data.endIndex else { throw LoadError.truncated }
            let result = [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                data.copyBytes(to: UnsafeMutableRawBufferPointer(buffer).bindMemory(to: UInt8.self),
                               from: offset..<offset + byteCount)
                initialized = count
            }
            offset += byteCount
            return result
        }
    }
}
