import Foundation

/// One saved LLM endpoint: an OpenAI Responses API, or a Chat Completions
/// API (DeepSeek, Ollama, …).
public struct Provider: Decodable, Equatable {
    public enum API: String {
        case responses
        case chat
    }

    public var name: String
    public var api: API
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var reasoningEffort: String?

    public init(name: String = "", api: API = .responses, baseURL: String, apiKey: String, model: String,
                reasoningEffort: String? = nil) {
        self.name = name
        self.api = api
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case name, api, baseURL, apiKey, model, reasoningEffort
    }

    /// Any field may be missing or of the wrong type: it then reads as empty,
    /// and the provider as not set up, rather than the whole file as broken.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            (try? c.decodeIfPresent(String.self, forKey: key))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        name = text(.name)
        api = API(rawValue: text(.api).lowercased()) ?? .responses
        baseURL = text(.baseURL)
        apiKey = text(.apiKey)
        model = text(.model)
        reasoningEffort = try? c.decodeIfPresent(String.self, forKey: .reasoningEffort)
    }

    /// Usable once it has a real API key.
    public var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != AppConfig.placeholderKey && !model.isEmpty && !baseURL.isEmpty
    }
}

/// An array element that may not decode; it is then skipped.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public struct AppConfig: Decodable, Equatable {
    /// The endpoint of a config from before `providers`: used only while
    /// that list is empty.
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var reasoningEffort: String?
    /// Saved endpoints; `provider` names the one in use, else it is the first.
    public var providers: [Provider]
    public var provider: String?
    /// The user's own prompt per mode, by `Mode.promptKey`, in place of the
    /// built-in one.
    public var prompts: [String: String]
    /// Panel color scheme: "auto" (follow system), "light", or "dark".
    public var appearance: String?
    /// What ⇧⇧ shows: "badge" (the FL badge alone, the default), "pill"
    /// (badge and On/Off in a capsule), "bubble" (badge and On/Off in a
    /// bubble pointing at the caret) or "keys" (that bubble with the badge
    /// alone, and the ⇧⇧ keys when off).
    public var toggleNotice: String?
    /// Terminal handling: "auto" (detect terminal apps), "always", or "never".
    /// Terminals clip marked text at the window edge, so for them the panel
    /// also shows the typed text once the composition nears the edge.
    public var terminalMode: String?
    /// Extra bundle identifiers to treat as terminals, on top of the
    /// built-in whitelist in `TerminalClients`.
    public var terminalApps: [String]?
    /// Exact terminal cell width in points, for clients that report neither
    /// a cell-sized caret rect nor a font. Omit/0 to estimate automatically.
    public var terminalCellWidth: Double?
    /// Chinese input: "pinyin" (full pinyin, the default), "xiaohe"
    /// (小鹤双拼) or "off". One layout at a time.
    public var chinese: String?
    /// Full pinyin: an initial alone spells a syllable (`zg` → 中国).
    /// Default on.
    public var pinyinAbbreviations: Bool?
    /// Full pinyin: pairs spelled alike, such as `"zh=z"` or `"an=ang"`.
    public var fuzzyPinyin: [String]?
    public var debounceMs: Int
    public var timeoutSeconds: Double

    public static let placeholderKey = "sk-REPLACE_ME"

    public static let defaultDebounceMs = 350
    public static let defaultTimeoutSeconds = 10.0
    /// Accepted ranges; out-of-range values are clamped rather than rejected
    /// so one bad number does not turn the whole config into "not configured".
    public static let debounceMsRange = 0...10_000
    public static let timeoutSecondsRange = 1.0...300.0

    static func clampDebounce(_ ms: Int) -> Int {
        min(max(ms, debounceMsRange.lowerBound), debounceMsRange.upperBound)
    }

    static func clampTimeout(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultTimeoutSeconds }
        return min(max(seconds, timeoutSecondsRange.lowerBound), timeoutSecondsRange.upperBound)
    }

    public init(baseURL: String = "", apiKey: String = "", model: String = "", reasoningEffort: String? = nil,
                providers: [Provider] = [], provider: String? = nil, prompts: [String: String] = [:],
                appearance: String? = nil, toggleNotice: String? = nil, terminalMode: String? = nil,
                terminalApps: [String]? = nil, terminalCellWidth: Double? = nil,
                chinese: String? = nil, pinyinAbbreviations: Bool? = nil, fuzzyPinyin: [String]? = nil,
                debounceMs: Int = AppConfig.defaultDebounceMs,
                timeoutSeconds: Double = AppConfig.defaultTimeoutSeconds) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.providers = providers
        self.provider = provider
        self.prompts = prompts
        self.appearance = appearance
        self.toggleNotice = toggleNotice
        self.terminalMode = terminalMode
        self.terminalApps = terminalApps
        self.terminalCellWidth = terminalCellWidth
        self.chinese = chinese
        self.pinyinAbbreviations = pinyinAbbreviations
        self.fuzzyPinyin = fuzzyPinyin
        self.debounceMs = AppConfig.clampDebounce(debounceMs)
        self.timeoutSeconds = AppConfig.clampTimeout(timeoutSeconds)
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, apiKey, model, reasoningEffort, providers, provider, prompts, appearance, toggleNotice,
             terminalMode, terminalApps, terminalCellWidth, chinese, pinyinAbbreviations, fuzzyPinyin,
             debounceMs, timeoutSeconds
    }

    /// Normalized appearance preference; unknown/missing values mean "auto".
    public var appearancePreference: String {
        switch appearance?.lowercased() {
        case "light": return "light"
        case "dark": return "dark"
        default: return "auto"
        }
    }

    /// Normalized ⇧⇧ notice; unknown/missing values mean "badge".
    public var toggleNoticePreference: String {
        switch toggleNotice?.lowercased() {
        case "pill": return "pill"
        case "bubble": return "bubble"
        case "keys": return "keys"
        default: return "badge"
        }
    }

    /// Normalized terminal-mode preference; unknown/missing values mean "auto".
    public var terminalModePreference: String {
        switch terminalMode?.lowercased() {
        case "always": return "always"
        case "never": return "never"
        default: return "auto"
        }
    }

    /// Normalized Chinese input; unknown/missing values mean "pinyin".
    public var chinesePreference: String {
        switch chinese?.lowercased() {
        case "xiaohe": return "xiaohe"
        case "off": return "off"
        default: return "pinyin"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Pasted values often bring a stray space or newline along; a newline
        // in the key silently drops the Authorization header.
        func required(_ key: CodingKeys) throws -> String {
            try c.decode(String.self, forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A wrong type for an optional key leaves it unset, rather than
        // turning the whole file into "not configured".
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            try? c.decodeIfPresent(type, forKey: key)
        }
        // Only objects count as providers; with none, the top-level keys are
        // the endpoint, as before there was a list.
        providers = optional([Lenient<Provider>].self, .providers)?.compactMap(\.value) ?? []
        if providers.isEmpty {
            baseURL = try required(.baseURL)
            apiKey = try required(.apiKey)
            model = try required(.model)
        } else {
            func text(_ key: CodingKeys) -> String {
                optional(String.self, key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
            baseURL = text(.baseURL)
            apiKey = text(.apiKey)
            model = text(.model)
        }
        reasoningEffort = optional(String.self, .reasoningEffort)
        provider = optional(String.self, .provider)
        prompts = optional([String: Lenient<String>].self, .prompts)?.compactMapValues(\.value) ?? [:]
        appearance = optional(String.self, .appearance)
        toggleNotice = optional(String.self, .toggleNotice)
        terminalMode = optional(String.self, .terminalMode)
        terminalApps = optional([String].self, .terminalApps)
        terminalCellWidth = optional(Double.self, .terminalCellWidth)
        chinese = optional(String.self, .chinese)
        pinyinAbbreviations = optional(Bool.self, .pinyinAbbreviations)
        fuzzyPinyin = optional([String].self, .fuzzyPinyin)
        let range = AppConfig.debounceMsRange
        let debounce = optional(Int.self, .debounceMs) ?? optional(Double.self, .debounceMs).map {
            Int(min(max($0.rounded(), Double(range.lowerBound)), Double(range.upperBound)))  // 350.5
        }
        debounceMs = AppConfig.clampDebounce(debounce ?? AppConfig.defaultDebounceMs)
        timeoutSeconds = AppConfig.clampTimeout(
            optional(Double.self, .timeoutSeconds) ?? AppConfig.defaultTimeoutSeconds)
    }

    /// Which of `providers` is in use: the one `provider` names, else the
    /// first; nil when the top-level keys are the endpoint.
    public var activeProviderIndex: Int? {
        guard !providers.isEmpty else { return nil }
        let name = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        return providers.firstIndex { $0.name == name } ?? 0
    }

    /// The endpoint requests go to.
    public var activeProvider: Provider {
        guard let index = activeProviderIndex else {
            return Provider(baseURL: baseURL, apiKey: apiKey, model: model, reasoningEffort: reasoningEffort)
        }
        return providers[index]
    }

    /// A config is usable once the provider in use has a real API key.
    public var isConfigured: Bool { activeProvider.isConfigured }

    /// The system instructions for `mode`: the user's own prompt, if any.
    public func instructions(for mode: Mode) -> String {
        mode.instructions(prompt: prompts[mode.promptKey])
    }
}

/// Loads `~/.config/fluent/config.json`, re-reading it whenever the
/// file's mtime changes (so "Reload Config" is mostly a formality). The
/// Settings app (Go, `Settings/`) shares no code with this: the file's keys
/// and rules are the contract between them, in docs/config.md.
public final class ConfigStore {
    public let configURL: URL
    private var cached: AppConfig?
    private var cachedMtime: Date?
    /// Why the file can't be used (not JSON, a required key missing), for
    /// the bar; nil when it loads or doesn't exist.
    public private(set) var problem: String?

    public init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configURL = home.appendingPathComponent(".config/fluent/config.json")
            ConfigStore.migrate(from: home.appendingPathComponent(".config/english-input/config.json"),
                                to: self.configURL)
        }
    }

    /// Fluent was called English Input before: carry its config over once,
    /// leaving the original in place.
    static func migrate(from legacy: URL, to url: URL) {
        let files = FileManager.default
        guard !files.fileExists(atPath: url.path), files.fileExists(atPath: legacy.path) else { return }
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        try? files.copyItem(at: legacy, to: url)
        try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func current() -> AppConfig? {
        // Through a symlink (dotfiles) to the file itself, so edits to it
        // are noticed.
        let path = configURL.resolvingSymlinksInPath().path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = attributes?[.modificationDate] as? Date
        if mtime == cachedMtime, cached != nil { return cached }
        cachedMtime = mtime
        cached = nil
        problem = nil
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        // It holds an API key: readable by you only.
        if let mode = attributes?[.posixPermissions] as? Int, mode & 0o077 != 0 {
            try? FileManager.default.setAttributes([.posixPermissions: mode & 0o700], ofItemAtPath: path)
        }
        do {
            cached = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            problem = Self.describe(error)
        }
        return cached
    }

    static func describe(_ error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, _)?:
            return "\"\(key.stringValue)\" is missing"
        case .typeMismatch(_, let context)?, .valueNotFound(_, let context)?:
            guard !context.codingPath.isEmpty else { return "not a JSON object" }  // `[…]`, `null`
            return "\"\(context.codingPath.map(\.stringValue).joined(separator: "."))\" has the wrong type"
        default:
            return "not valid JSON"
        }
    }

    public func invalidate() {
        cached = nil
        cachedMtime = nil
    }

    /// Sets one key in the config file (nil removes it), editing only that
    /// key's text: the others keep their order and formatting. Used by the
    /// IME menu and the Settings app. False when the file isn't a JSON
    /// object, which is then left alone.
    @discardableResult
    public func set(_ key: String, to value: Any?) -> Bool {
        writeTemplateIfMissing()
        guard let data = try? Data(contentsOf: configURL),
              let output = JSONEdit.setting(key, to: value, in: String(decoding: data, as: UTF8.self))
        else { return false }
        // Into the file a symlink points at, keeping the link.
        let target = configURL.resolvingSymlinksInPath()
        let written = (try? Data(output.utf8).write(to: target, options: .atomic)) != nil
        invalidate()
        return written
    }

    /// Writes a starter config the user can edit; no-op if the file exists.
    @discardableResult
    public func writeTemplateIfMissing() -> Bool {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return false }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let template = """
        {
          "baseURL": "https://api.openai.com/v1",
          "apiKey": "\(AppConfig.placeholderKey)",
          "model": "gpt-4o-mini",
          "appearance": "auto",
          "terminalMode": "auto",
          "chinese": "pinyin",
          "debounceMs": 350,
          "timeoutSeconds": 10
        }
        """
        // It will hold an API key: readable by you only.
        return FileManager.default.createFile(atPath: configURL.path, contents: Data(template.utf8),
                                              attributes: [.posixPermissions: 0o600])
    }
}
