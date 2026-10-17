import Foundation
import os.log
import FluentCore

private let spLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "shuangpin")

/// The 小鹤双拼 dictionary bundled by `make dict`, loaded off the main
/// thread at launch, plus the words learned from your picks. Until it is
/// loaded (or if the bundle has none) typing stays English only.
final class Shuangpin {
    private(set) static var shared: Shuangpin?

    let translator: XiaoheTranslator
    private let userDictionary: UserDictionary
    private var pendingSave: DispatchWorkItem?

    static let userDictionaryURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fluent/xiaohe-user.tsv")

    private init(lexicon: Lexicon, userDictionary: UserDictionary) {
        translator = XiaoheTranslator(lexicon: lexicon, userDictionary: userDictionary)
        self.userDictionary = userDictionary
    }

    /// Learns the words of a commit; saved a moment later, off the main thread.
    func learn(_ words: [(text: String, code: [SyllableID])]) {
        userDictionary.learn(words)
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.userDictionary.serialized()
            DispatchQueue.global(qos: .utility).async {
                do {
                    let url = Shuangpin.userDictionaryURL
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try text.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    spLog.error("saving learned words failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    static func preload() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let lexiconURL = Bundle.main.url(forResource: "xiaohe", withExtension: "lexicon") else {
                spLog.error("no shuangpin dictionary in the bundle (make dict)")
                return
            }
            do {
                let start = Date()
                // A missing or unreadable file just means nothing learned yet.
                let learned = (try? UserDictionary(contentsOf: userDictionaryURL)) ?? UserDictionary()
                let engine = Shuangpin(lexicon: try Lexicon(contentsOf: lexiconURL), userDictionary: learned)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                spLog.notice("shuangpin dictionary loaded: \(engine.translator.lexicon.count, privacy: .public) entries, \(learned.count, privacy: .public) learned, in \(ms, privacy: .public) ms")
                DispatchQueue.main.async { shared = engine }
            } catch {
                spLog.error("shuangpin dictionary failed to load: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
