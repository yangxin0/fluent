import Foundation
import EnglishInputCore

// Debug harness: exercises the streaming client outside the IME loop.
//   swift run english-input-cli [--mode fix|polish|interpret] "helo wrold"

var mode = Mode.fix
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
    } else {
        words.append(arg)
    }
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
