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
        self.debounceMs = AppConfig.clampDebounce(debounceMs)
        self.timeoutSeconds = AppConfig.clampTimeout(timeoutSeconds)
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, apiKey, model, reasoningEffort, appearance, terminalMode, terminalApps,
             terminalCellWidth, debounceMs, timeoutSeconds
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        model = try c.decode(String.self, forKey: .model)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance)
        terminalMode = try c.decodeIfPresent(String.self, forKey: .terminalMode)
        terminalApps = try c.decodeIfPresent([String].self, forKey: .terminalApps)
        terminalCellWidth = try c.decodeIfPresent(Double.self, forKey: .terminalCellWidth)
        debounceMs = AppConfig.clampDebounce(
            try c.decodeIfPresent(Int.self, forKey: .debounceMs) ?? AppConfig.defaultDebounceMs)
        timeoutSeconds = AppConfig.clampTimeout(
            try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? AppConfig.defaultTimeoutSeconds)
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
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.copyItem(at: legacy, to: url)
    }

    public func current() -> AppConfig? {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate]) as? Date
        if mtime == cachedMtime, cached != nil { return cached }
        cachedMtime = mtime
        cached = nil
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        cached = try? JSONDecoder().decode(AppConfig.self, from: data)
        return cached
    }

    public func invalidate() {
        cached = nil
        cachedMtime = nil
    }

    /// Writes a starter config the user can edit; no-op if the file exists.
    @discardableResult
    public func writeTemplateIfMissing() -> Bool {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return false }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let template = """
        {
          "baseURL": "https://api.openai.com/v1",
          "apiKey": "\(AppConfig.placeholderKey)",
          "model": "gpt-4o-mini",
          "appearance": "auto",
          "terminalMode": "auto",
          "debounceMs": 350,
          "timeoutSeconds": 10
        }
        """
        return (try? template.write(to: configURL, atomically: true, encoding: .utf8)) != nil
    }
}
