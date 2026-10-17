import Foundation
import os.log
import EnglishInputCore

private let spLog = Logger(subsystem: "com.yangxin.inputmethod.EnglishInput", category: "shuangpin")

/// The 小鹤双拼 dictionary bundled by `make dict`, loaded off the main
/// thread at launch. Until it is loaded (or if the bundle has none) typing
/// stays English only.
final class Shuangpin {
    private(set) static var shared: Shuangpin?

    let translator: XiaoheTranslator
    let english: EnglishWords

    private init(translator: XiaoheTranslator, english: EnglishWords) {
        self.translator = translator
        self.english = english
    }

    static func preload() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let lexiconURL = Bundle.main.url(forResource: "xiaohe", withExtension: "lexicon"),
                  let englishURL = Bundle.main.url(forResource: "english", withExtension: "txt")
            else {
                spLog.error("no shuangpin dictionary in the bundle (make dict)")
                return
            }
            do {
                let start = Date()
                let engine = Shuangpin(translator: XiaoheTranslator(lexicon: try Lexicon(contentsOf: lexiconURL)),
                                       english: try EnglishWords(contentsOf: englishURL))
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                spLog.notice("shuangpin dictionary loaded: \(engine.translator.lexicon.count, privacy: .public) entries, \(engine.english.count, privacy: .public) English words in \(ms, privacy: .public) ms")
                DispatchQueue.main.async { shared = engine }
            } catch {
                spLog.error("shuangpin dictionary failed to load: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
