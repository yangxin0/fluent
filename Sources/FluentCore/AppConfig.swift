import Foundation

public struct AppConfig: Codable, Equatable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var reasoningEffort: String?
    /// Panel color scheme: "auto" (follow system), "light", or "dark".
    public var appearance: String?
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
    /// Chinese input: "xiaohe" (小鹤双拼, the default), "pinyin" (full
    /// pinyin) or "off". One layout at a time.
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

    public init(baseURL: String, apiKey: String, model: String, reasoningEffort: String? = nil,
                appearance: String? = nil, terminalMode: String? = nil,
                terminalApps: [String]? = nil, terminalCellWidth: Double? = nil,
                chinese: String? = nil, pinyinAbbreviations: Bool? = nil, fuzzyPinyin: [String]? = nil,
                debounceMs: Int = AppConfig.defaultDebounceMs,
                timeoutSeconds: Double = AppConfig.defaultTimeoutSeconds) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.appearance = appearance
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
        case baseURL, apiKey, model, reasoningEffort, appearance, terminalMode, terminalApps,
             terminalCellWidth, chinese, pinyinAbbreviations, fuzzyPinyin, debounceMs, timeoutSeconds
    }

    /// Normalized appearance preference; unknown/missing values mean "auto".
    public var appearancePreference: String {
        switch appearance?.lowercased() {
        case "light": return "light"
        case "dark": return "dark"
        default: return "auto"
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

    /// Normalized Chinese input; unknown/missing values mean "xiaohe".
    public var chinesePreference: String {
        switch chinese?.lowercased() {
        case "pinyin", "quanpin": return "pinyin"
        case "off": return "off"
        default: return "xiaohe"
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
        baseURL = try required(.baseURL)
        apiKey = try required(.apiKey)
        model = try required(.model)
        reasoningEffort = optional(String.self, .reasoningEffort)
        appearance = optional(String.self, .appearance)
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

    /// A config is usable once the user has filled in a real API key.
    public var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != AppConfig.placeholderKey && !model.isEmpty && !baseURL.isEmpty
    }
}

/// Loads `~/.config/fluent/config.json`, re-reading it whenever the
/// file's mtime changes (so "Reload Config" is mostly a formality).
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
          "chinese": "xiaohe",
          "debounceMs": 350,
          "timeoutSeconds": 10
        }
        """
        // It will hold an API key: readable by you only.
        return FileManager.default.createFile(atPath: configURL.path, contents: Data(template.utf8),
                                              attributes: [.posixPermissions: 0o600])
    }
}
