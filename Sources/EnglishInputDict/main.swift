import Foundation
import EnglishInputCore

// Compiles rime-ice's dictionaries into the files the IME loads (`make dict`):
//   swift run english-input-dict [--min-weight N] <rime-ice dir> <output dir>
// Output: xiaohe.lexicon (characters + words by syllable code) and
// english.txt (lowercase English words, one per line).

var minWeight = 100.0
var paths: [String] = []
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    if arg == "--min-weight", let value = args.first.flatMap(Double.init) {
        args.removeFirst()
        minWeight = value
    } else {
        paths.append(arg)
    }
}
guard paths.count == 2 else {
    FileHandle.standardError.write(Data("usage: english-input-dict [--min-weight N] <rime-ice dir> <output dir>\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: paths[0])
let output = URL(fileURLWithPath: paths[1])

/// Tab-separated rows after a Rime dictionary's `...` header terminator,
/// skipping comments and blank lines.
func rows(of file: String) throws -> [[Substring]] {
    let text = try String(contentsOf: source.appendingPathComponent(file), encoding: .utf8)
    var result: [[Substring]] = []
    var inBody = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
        if !inBody {
            inBody = line == "..."
            continue
        }
        guard !line.hasPrefix("#") else { continue }
        result.append(line.split(separator: "\t", omittingEmptySubsequences: false))
    }
    return result
}

struct Key: Hashable {
    var text: Substring
    var code: [SyllableID]
}

var weights: [Key: Double] = [:]
var skipped = 0

/// `onlyAbove` drops the long tail of rare words to keep the bundle small;
/// characters are all kept so every syllable can still be spelled.
func load(_ file: String, onlyAbove threshold: Double) throws {
    for row in try rows(of: file) where row.count >= 2 {
        let weight = row.count >= 3 ? Double(row[2]) ?? 0 : 0
        guard weight >= threshold else { continue }
        var code: [SyllableID] = []
        for syllable in row[1].split(separator: " ") {
            guard let id = Pinyin.id(of: String(syllable)) else { break }
            code.append(id)
        }
        guard !code.isEmpty, code.count == row[1].split(separator: " ").count else {
            skipped += 1
            continue
        }
        let key = Key(text: row[0], code: code)
        weights[key] = max(weights[key] ?? 0, weight)
    }
}

do {
    try load("cn_dicts/8105.dict.yaml", onlyAbove: 0)
    try load("cn_dicts/base.dict.yaml", onlyAbove: minWeight)
    let entries = weights.map { key, weight in
        Lexicon.Entry(text: String(key.text), code: key.code, weight: Lexicon.normalizedWeight(weight))
    }
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let lexicon = Lexicon.encode(entries)
    try lexicon.write(to: output.appendingPathComponent("xiaohe.lexicon"))

    // rime-ice comments out single letters and most two-letter words (they
    // are mostly abbreviations); bring back the real ones so `an` is English.
    // Capitalized entries (names, acronyms) are left out: see EnglishWords.
    let restored = ["a", "i", "an", "oh", "ah", "eh", "ha", "uh", "um", "ox", "ye", "yo"]
    let english = Set(try rows(of: "en_dicts/en.dict.yaml").compactMap { $0.first.map(String.init) } + restored)
        .filter { $0.utf8.allSatisfy { $0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z") } }
        .sorted()
    try (english.joined(separator: "\n") + "\n")
        .write(to: output.appendingPathComponent("english.txt"), atomically: true, encoding: .utf8)

    print("xiaohe.lexicon: \(entries.count) entries (\(lexicon.count / 1024) KB), "
          + "skipped \(skipped) with unknown syllables; english.txt: \(english.count) words")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
