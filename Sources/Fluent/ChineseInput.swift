import Foundation
import os.log
import FluentCore

private let spLog = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "chinese")

/// The Chinese dictionary bundled by `make dict`, loaded off the main
/// thread at launch, plus the words learned from your picks. Until it is
/// loaded (or if the bundle has none) typing stays English only. The layout
/// (小鹤双拼 or full pinyin) follows the config.
final class ChineseInput {
    private(set) static var shared: ChineseInput?

    let translator: ChineseTranslator
    let english: EnglishWords
    private let userDictionary: UserDictionary
    private var pendingSave: DispatchWorkItem?
    private var layoutSettings: LayoutSettings?

    private struct LayoutSettings: Equatable {
        var layout: String
        var abbreviations: Bool
        var fuzzy: [String]
    }

    static let userDictionaryURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fluent/xiaohe-user.tsv")

    private init(lexicon: Lexicon, english: EnglishWords, userDictionary: UserDictionary) {
        translator = ChineseTranslator(lexicon: lexicon, userDictionary: userDictionary)
        self.english = english
        self.userDictionary = userDictionary
    }

    /// Points the translator at the configured layout, rebuilding it only when
    /// the settings change. False when Chinese is off.
    func apply(_ config: AppConfig?) -> Bool {
        let settings = LayoutSettings(layout: config?.chinesePreference ?? "xiaohe",
                                      abbreviations: config?.pinyinAbbreviations ?? true,
                                      fuzzy: config?.fuzzyPinyin ?? [])
        guard settings.layout != "off" else { return false }
        if settings != layoutSettings {
            translator.layout = settings.layout == "pinyin"
                ? FullPinyinLayout(abbreviations: settings.abbreviations, fuzzy: settings.fuzzy)
                : XiaoheLayout()
            layoutSettings = settings
        }
        return true
    }

    /// `'` separates syllables in full pinyin (`xi'an`).
    var separatesSyllables: Bool { translator.layout is FullPinyinLayout }

    /// The candidate bar's badge: `拼` for full pinyin, `双` for shuangpin.
    var badge: String { translator.layout is FullPinyinLayout ? "拼" : "双" }

    /// Learns the words of a commit; saved a moment later, off the main thread.
    func learn(_ words: [(text: String, code: [SyllableID])]) {
        userDictionary.learn(words)
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.userDictionary.serialized()
            DispatchQueue.global(qos: .utility).async {
                do {
                    let url = ChineseInput.userDictionaryURL
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
            guard let lexiconURL = Bundle.main.url(forResource: "xiaohe", withExtension: "lexicon"),
                  let englishURL = Bundle.main.url(forResource: "english", withExtension: "txt")
            else {
                spLog.error("no shuangpin dictionary in the bundle (make dict)")
                return
            }
            do {
                let start = Date()
                // A missing or unreadable file just means nothing learned yet.
                let learned = (try? UserDictionary(contentsOf: userDictionaryURL)) ?? UserDictionary()
                let engine = ChineseInput(lexicon: try Lexicon(contentsOf: lexiconURL),
                                       english: try EnglishWords(contentsOf: englishURL), userDictionary: learned)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                spLog.notice("shuangpin dictionary loaded: \(engine.translator.lexicon.count, privacy: .public) entries, \(engine.english.count, privacy: .public) English words, \(learned.count, privacy: .public) learned, in \(ms, privacy: .public) ms")
                DispatchQueue.main.async { shared = engine }
            } catch {
                spLog.error("shuangpin dictionary failed to load: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
