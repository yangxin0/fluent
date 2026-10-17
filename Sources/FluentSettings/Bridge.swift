import AppKit
import Carbon
import FluentCore
import WebKit

/// What the pages ask of the app, as `await fluent(op, args)`: the config
/// file, the state of the input method, and a few actions.
final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    static let inputSourceID = "com.yangxin.inputmethod.Fluent"
    static let inputMethodURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods/Fluent-Input.app")
    static let inputSourcesSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
    static let repository = URL(string: "https://github.com/yangxin0/fluent")!
    /// The config keys the pages may set (AppConfig's).
    static let keys: Set<String> = [
        "baseURL", "apiKey", "model", "reasoningEffort", "debounceMs", "timeoutSeconds", "appearance",
        "terminalMode", "terminalApps", "terminalCellWidth", "chinese", "pinyinAbbreviations", "fuzzyPinyin",
    ]

    private let store = ConfigStore()
    weak var window: NSWindow?

    override init() {
        super.init()
        store.writeTemplateIfMissing()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler reply: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            return reply(nil, "bad message")
        }
        let args = body["args"] as? [String: Any] ?? [:]
        switch op {
        case "status":
            reply(status(), nil)
        case "config.get":
            store.writeTemplateIfMissing()
            let data = (try? Data(contentsOf: store.configURL)) ?? Data()
            reply((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:], nil)
        case "config.set":
            guard let key = args["key"] as? String, Self.keys.contains(key) else { return reply(nil, "unknown key") }
            let value = args["value"].flatMap { $0 is NSNull ? nil : $0 }
            reply(["ok": store.set(key, to: value)], nil)
        case "test":
            test(reply)
        case "learned.forget":
            forgetLearned(args, reply)
        case "prefs.get":
            reply(["language": UserDefaults.standard.string(forKey: "language") ?? "system",
                   "system": Locale.preferredLanguages.first ?? "en"], nil)
        case "prefs.set":
            if let language = args["language"] as? String { UserDefaults.standard.set(language, forKey: "language") }
            reply(["ok": true], nil)
        case "open":
            switch args["what"] as? String {
            case "inputSources": NSWorkspace.shared.open(Self.inputSourcesSettings)
            case "config": NSWorkspace.shared.open(store.configURL)
            case "repository": NSWorkspace.shared.open(Self.repository)
            default: return reply(nil, "unknown target")
            }
            reply(["ok": true], nil)
        default:
            reply(nil, "unknown op \(op)")
        }
    }

    // MARK: - Status

    private func status() -> [String: Any] {
        let files = FileManager.default
        let config = store.current()
        let resources = Self.inputMethodURL.appendingPathComponent("Contents/Resources")
        let modified = (try? files.attributesOfItem(atPath: store.configURL.resolvingSymlinksInPath().path))?[
            .modificationDate] as? Date
        return [
            "installed": files.fileExists(atPath: Self.inputMethodURL.path),
            "enabled": Self.inputSource(enabledOnly: true) != nil,
            "selected": Self.currentInputSourceID() == Self.inputSourceID,
            "configured": config?.isConfigured ?? false,
            "configProblem": store.problem ?? NSNull(),
            "dictionaries": ["xiaohe.lexicon", "english.txt"].allSatisfy {
                files.fileExists(atPath: resources.appendingPathComponent($0).path)
            },
            "learned": (try? UserDictionary(contentsOf: UserDictionary.fileURL))?.count ?? 0,
            "configStamp": modified?.timeIntervalSince1970 ?? 0,
            "configPath": (store.configURL.path as NSString).abbreviatingWithTildeInPath,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        ]
    }

    /// Fluent's input source; with `enabledOnly`, only once it's added in
    /// System Settings ▸ Keyboard ▸ Input Sources.
    static func inputSource(enabledOnly: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        let list = TISCreateInputSourceList(filter, !enabledOnly)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    static func currentInputSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    // MARK: - Actions

    /// One tiny request with the saved settings: the reply, or why it failed.
    private func test(_ reply: @escaping (Any?, String?) -> Void) {
        store.invalidate()
        guard let config = store.current(), config.isConfigured else {
            return reply(["ok": false, "code": store.problem == nil ? "notConfigured" : "configError",
                          "error": store.problem ?? ""], nil)
        }
        let input = "helo wrld"
        let started = Date()
        Task { @MainActor in
            do {
                var text = ""
                for try await delta in ResponsesClient().stream(config: config, instructions: Mode.fix.instructions,
                                                                input: input) {
                    text += delta
                }
                reply(["ok": true, "input": input, "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                       "ms": Int(Date().timeIntervalSince(started) * 1000)], nil)
            } catch {
                reply(["ok": false, "error": RewriteEngine.humanize(error)], nil)
            }
        }
    }

    /// Asks first (the page passes the wording in its language), then
    /// deletes the file and tells a running IME to forget its copy.
    private func forgetLearned(_ args: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let window else { return reply(["ok": false], nil) }
        let alert = NSAlert()
        alert.messageText = args["title"] as? String ?? "Forget learned words?"
        alert.informativeText = args["detail"] as? String ?? ""
        alert.addButton(withTitle: args["confirm"] as? String ?? "Forget")
        alert.addButton(withTitle: args["cancel"] as? String ?? "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return reply(["ok": false], nil) }
            try? FileManager.default.removeItem(at: UserDictionary.fileURL)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(UserDictionary.forgetNotification), object: nil, userInfo: nil,
                deliverImmediately: true)
            reply(["ok": true], nil)
        }
    }
}
