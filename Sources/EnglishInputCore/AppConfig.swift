import Foundation

public struct AppConfig: Codable, Equatable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    public var reasoningEffort: String?
    /// Panel color scheme: "auto" (follow system), "light", or "dark".
    public var appearance: String?
    public var debounceMs: Int
    public var timeoutSeconds: Double

    public static let placeholderKey = "sk-REPLACE_ME"

    public init(baseURL: String, apiKey: String, model: String, reasoningEffort: String? = nil,
                appearance: String? = nil, debounceMs: Int = 350, timeoutSeconds: Double = 10) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.appearance = appearance
        self.debounceMs = debounceMs
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, apiKey, model, reasoningEffort, appearance, debounceMs, timeoutSeconds
    }

    /// Normalized appearance preference; unknown/missing values mean "auto".
    public var appearancePreference: String {
        switch appearance?.lowercased() {
        case "light": return "light"
        case "dark": return "dark"
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
        debounceMs = try c.decodeIfPresent(Int.self, forKey: .debounceMs) ?? 350
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 10
    }

    /// A config is usable once the user has filled in a real API key.
    public var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != AppConfig.placeholderKey && !model.isEmpty && !baseURL.isEmpty
    }
}

/// Loads `~/.config/english-input/config.json`, re-reading it whenever the
/// file's mtime changes (so "Reload Config" is mostly a formality).
public final class ConfigStore {
    public let configURL: URL
    private var cached: AppConfig?
    private var cachedMtime: Date?

    public init(configURL: URL? = nil) {
        self.configURL = configURL
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/english-input/config.json")
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
          "debounceMs": 350,
          "timeoutSeconds": 10
        }
        """
        return (try? template.write(to: configURL, atomically: true, encoding: .utf8)) != nil
    }
}
