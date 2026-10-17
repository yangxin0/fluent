import Foundation
import EnglishInputCore

// Debug harness: exercises the streaming client outside the IME loop.
//   swift run english-input-cli [--mode fix|polish|interpret] "helo wrold"
// or the shuangpin engine against the compiled dictionary (`make dict`):
//   swift run english-input-cli --xiaohe [--dict .build/dict] veui nihc

var mode = Mode.fix
var xiaohe = false
var dictDirectory = ".build/dict"
var words: [String] = []
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    if arg == "--mode" {
        guard !args.isEmpty, let m = Mode(rawValue: args.removeFirst()) else {
            FileHandle.standardError.write(Data("invalid --mode (fix|polish|interpret)\n".utf8))
            exit(2)
        }
        mode = m
    } else if arg == "--xiaohe" {
        xiaohe = true
    } else if arg == "--dict", !args.isEmpty {
        dictDirectory = args.removeFirst()
    } else {
        words.append(arg)
    }
}

if xiaohe {
    let directory = URL(fileURLWithPath: dictDirectory)
    do {
        let translator = XiaoheTranslator(
            lexicon: try Lexicon(contentsOf: directory.appendingPathComponent("xiaohe.lexicon")))
        let english = try EnglishWords(contentsOf: directory.appendingPathComponent("english.txt"))
        for keys in words {
            let rank = ShuangpinPolicy.rank(run: keys, context: .fresh, english: english)
            print("\(Xiaohe.grouped(keys))  [\(rank)]")
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
guard !input.isEmpty else {
    FileHandle.standardError.write(Data("usage: english-input-cli [--mode fix|polish|interpret] <text>\n".utf8))
    exit(2)
}

let store = ConfigStore()
store.writeTemplateIfMissing()
guard let config = store.current(), config.isConfigured else {
    FileHandle.standardError.write(Data("Config missing or incomplete: \(store.configURL.path)\n".utf8))
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
