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
    private(set) var english: EnglishWords
    private let userDictionary: UserDictionary
    /// When your English words file was last read (or written here).
    private var englishWordsStamp: Date?
    private var pendingSave: DispatchWorkItem?
    /// One save at a time, so an older snapshot never replaces a newer one.
    private static let saveQueue = DispatchQueue(label: "com.yangxin.inputmethod.Fluent.save", qos: .utility)
    private var layoutSettings: LayoutSettings?

    private struct LayoutSettings: Equatable {
        var layout: String
        var abbreviations: Bool
        var fuzzy: [String]
    }

    static let userDictionaryURL = UserDictionary.fileURL

    private init(lexicon: Lexicon, english: EnglishWords, userDictionary: UserDictionary) {
        translator = ChineseTranslator(lexicon: lexicon, userDictionary: userDictionary)
        self.english = english
        self.userDictionary = userDictionary
    }

    /// Points the translator at the configured layout, rebuilding it only when
    /// the settings change. False when Chinese is off.
    func apply(_ config: AppConfig?) -> Bool {
        let settings = LayoutSettings(layout: config?.chinesePreference ?? "pinyin",
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
        guard userDictionary.learn(words) else { return }
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.userDictionary.serialized()
            ChineseInput.saveQueue.async {
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

    /// Rereads your English words when the file changed: Settings edits it.
    func refreshEnglishWords() {
        let url = EnglishWords.yoursFileURL
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        guard stamp != englishWordsStamp else { return }
        englishWordsStamp = stamp
        english.setYours(EnglishWords.yours(from: (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
    }

    /// Keys inserted as typed from the Chinese bar are a word Fluent didn't
    /// know (a product name): remembered as English from now on (#24).
    func learnEnglish(_ keys: String) {
        refreshEnglishWords()
        guard english.add(keys) else { return }
        let url = EnglishWords.yoursFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try EnglishWords.serialized(english.yours).write(to: url, atomically: true, encoding: .utf8)
            englishWordsStamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            spLog.notice("learned an English word (\(self.english.yours.count, privacy: .public) of yours)")
        } catch {
            spLog.error("saving English words failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Fluent Settings ▸ Chinese ▸ Forget learned words.
    func forgetLearned() {
        pendingSave?.cancel()
        userDictionary.reset()
        ChineseInput.saveQueue.async { try? FileManager.default.removeItem(at: ChineseInput.userDictionaryURL) }
        spLog.notice("forgot the learned words")
    }

    /// A missing file just means nothing learned yet; an unreadable one is
    /// kept aside rather than overwritten by the next save.
    private static func loadLearned() -> UserDictionary {
        let url = userDictionaryURL
        do {
            return try UserDictionary(contentsOf: url)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                let aside = url.appendingPathExtension("unreadable")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: url, to: aside)
                spLog.error("learned words unreadable, moved to \(aside.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return UserDictionary()
        }
    }

    static func preload() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(UserDictionary.forgetNotification), object: nil, queue: .main
        ) { _ in shared?.forgetLearned() }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let lexiconURL = Bundle.main.url(forResource: "xiaohe", withExtension: "lexicon"),
                  let englishURL = Bundle.main.url(forResource: "english", withExtension: "txt")
            else {
                spLog.error("no shuangpin dictionary in the bundle (make dict)")
                return
            }
            do {
                let start = Date()
                let learned = loadLearned()
                let engine = ChineseInput(lexicon: try Lexicon(contentsOf: lexiconURL),
                                       english: try EnglishWords(contentsOf: englishURL), userDictionary: learned)
                engine.refreshEnglishWords()
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                spLog.notice("shuangpin dictionary loaded: \(engine.translator.lexicon.count, privacy: .public) entries, \(engine.english.count, privacy: .public) English words, \(learned.count, privacy: .public) learned, in \(ms, privacy: .public) ms")
                DispatchQueue.main.async { shared = engine }
            } catch {
                spLog.error("shuangpin dictionary failed to load: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
