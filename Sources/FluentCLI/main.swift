import Foundation
import FluentCore

// Debug harness: exercises the streaming client outside the IME loop.
//   swift run fluent-cli [--mode fix|polish|interpret] "helo wrold"
// or the Chinese engine against the compiled dictionary (`make dict`), as
// 小鹤双拼 or full pinyin:
//   swift run fluent-cli --xiaohe [--dict .build/dict] veui nihc
//   swift run fluent-cli --pinyin [--no-abbreviations] [--fuzzy zh=z,an=ang] nihao zg

let usage = """
usage: fluent-cli [--mode fix|polish|interpret] TEXT…
       fluent-cli --xiaohe|--pinyin [--no-abbreviations] [--fuzzy zh=z,an=ang] [--dict DIR] KEYS…

"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n" + usage).utf8))
    exit(2)
}

var mode = Mode.fix
var xiaohe = false
var pinyin = false
var abbreviations = true
var fuzzy: [String] = []
var dictDirectory = ".build/dict"
var words: [String] = []
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    if arg == "--mode" {
        guard !args.isEmpty, let m = Mode(rawValue: args.removeFirst()) else { fail("invalid --mode") }
        mode = m
    } else if arg == "--xiaohe" {
        xiaohe = true
    } else if arg == "--pinyin" {
        pinyin = true
    } else if arg == "--no-abbreviations" {
        abbreviations = false
    } else if arg == "--fuzzy" {
        guard !args.isEmpty else { fail("--fuzzy needs pairs like zh=z,an=ang") }
        fuzzy = args.removeFirst().split(separator: ",").map(String.init)
    } else if arg == "--dict" {
        guard !args.isEmpty else { fail("--dict needs a directory") }
        dictDirectory = args.removeFirst()
    } else if arg == "--help" || arg == "-h" {
        print(usage, terminator: "")
        exit(0)
    } else if arg == "--" {
        words += args
        args = []
    } else if arg.hasPrefix("--") {
        // Never send a mistyped flag to the API as text.
        fail("unknown option \(arg)")
    } else {
        words.append(arg)
    }
}

if xiaohe || pinyin {
    let directory = URL(fileURLWithPath: dictDirectory)
    do {
        let layout: any KeyLayout = pinyin
            ? FullPinyinLayout(abbreviations: abbreviations, fuzzy: fuzzy) : XiaoheLayout()
        let translator = ChineseTranslator(
            lexicon: try Lexicon(contentsOf: directory.appendingPathComponent("xiaohe.lexicon")), layout: layout)
        let english = try EnglishWords(contentsOf: directory.appendingPathComponent("english.txt"))
        for keys in words {
            let rank = ChinesePolicy.rank(run: keys, context: .fresh, english: english, layout: layout)
            print("\(layout.grouped(keys))  [\(rank)]")
            for (index, candidate) in translator.candidates(for: keys).prefix(12).enumerated() {
                let comment = candidate.comment.map { " \($0)" } ?? ""
                let partial = candidate.keyCount < keys.count ? " (\(candidate.keyCount) keys)" : ""
                print(String(format: "  %2d %@%@%@  %.2f", index + 1, candidate.text, comment, partial,
                             candidate.weight))
            }
        }
    } catch {
        FileHandle.standardError.write(Data("cannot load \(dictDirectory) (run make dict): \(error)\n".utf8))
        exit(1)
    }
    exit(0)
}

let input = words.joined(separator: " ")
guard !input.isEmpty else { fail("nothing to rewrite") }

let store = ConfigStore()
store.writeTemplateIfMissing()
guard let config = store.current(), config.isConfigured else {
    let problem = store.problem.map { " (\($0))" } ?? ""
    FileHandle.standardError.write(Data("Config missing or incomplete\(problem): \(store.configURL.path)\n".utf8))
    exit(1)
}

FileHandle.standardError.write(Data("[\(mode.badge)] \(input)\n→ ".utf8))
do {
    let client = ResponsesClient()
    for try await delta in client.stream(config: config, instructions: mode.instructions, input: input) {
        print(delta, terminator: "")
        fflush(stdout)
    }
    print()
} catch {
    FileHandle.standardError.write(Data("\nerror: \(error.localizedDescription)\n".utf8))
    exit(1)
}
