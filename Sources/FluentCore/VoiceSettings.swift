import Foundation

/// A saved speech recognition engine (`voice.engines`): which service, and
/// its credentials. Any field may be missing or of the wrong type: it then
/// reads as empty, and the engine as not set up.
public struct VoiceEngine: Decodable, Equatable {
    /// The services Fluent can talk to; more are to come.
    public enum Kind: String {
        /// 豆包流式语音识别 (Volcengine, ByteDance).
        case volcengine
    }

    public static let defaultResourceId = "volc.seedasr.sauc.duration"

    public var name: String
    /// nil for a type this version doesn't know.
    public var kind: Kind?
    /// The new console's API key (`X-Api-Key`).
    public var apiKey: String
    /// The old console's App ID and Access Token (`X-Api-App-Key`,
    /// `X-Api-Access-Key`), used while there is no API key.
    public var appId: String
    public var accessToken: String
    /// The resource bought: model 1.0 or 2.0, by the hour or concurrent.
    public var resourceId: String

    public init(name: String = "", kind: Kind? = .volcengine, apiKey: String = "", appId: String = "",
                accessToken: String = "", resourceId: String = VoiceEngine.defaultResourceId) {
        self.name = name
        self.kind = kind
        self.apiKey = apiKey
        self.appId = appId
        self.accessToken = accessToken
        self.resourceId = resourceId
    }

    enum CodingKeys: String, CodingKey {
        case name, type, apiKey, appId, accessToken, resourceId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            (try? c.decodeIfPresent(String.self, forKey: key))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        name = text(.name)
        let type = text(.type).lowercased()
        kind = type.isEmpty ? .volcengine : Kind(rawValue: type)
        apiKey = text(.apiKey)
        appId = text(.appId)
        accessToken = text(.accessToken)
        let resource = text(.resourceId)
        resourceId = resource.isEmpty ? VoiceEngine.defaultResourceId : resource
    }

    /// Usable once it is of a known type and has credentials.
    public var isConfigured: Bool {
        kind != nil && (!apiKey.isEmpty || (!appId.isEmpty && !accessToken.isEmpty))
    }
}

/// Voice input (`voice`): the engines, and how a recording starts and ends.
public struct VoiceSettings: Decodable, Equatable {
    /// A modifier held alone to talk.
    public enum HoldKey: String, CaseIterable {
        case off
        case rightOption = "right-option"
        case rightCommand = "right-command"
        case fn
    }

    /// What the recognized text becomes.
    public enum AfterSpeaking: String {
        /// Inserted as is.
        case insert
        /// The composition, improved by the current mode like typed text.
        case improve
    }

    public var engines: [VoiceEngine] = []
    /// The `name` of the engine in use; else the first.
    public var engine: String?
    public var holdKey: HoldKey = .rightOption
    /// A `KeyCombo` name that starts and stops a recording; none by default.
    public var toggleKey: String?
    public var afterSpeaking: AfterSpeaking = .insert
    /// Send your English words to the engine as hotwords.
    public var hotwords = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case engines, engine, holdKey, toggleKey, afterSpeaking, hotwords
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func optional<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            try? c.decodeIfPresent(type, forKey: key)
        }
        engines = optional([LenientVoiceEngine].self, .engines)?.compactMap(\.value) ?? []
        engine = optional(String.self, .engine)
        holdKey = optional(String.self, .holdKey).flatMap { HoldKey(rawValue: $0.lowercased()) } ?? .rightOption
        toggleKey = optional(String.self, .toggleKey).flatMap(KeyCombo.normalized)
        afterSpeaking = optional(String.self, .afterSpeaking)
            .flatMap { AfterSpeaking(rawValue: $0.lowercased()) } ?? .insert
        hotwords = optional(Bool.self, .hotwords) ?? true
    }

    /// The engine in use: the one `engine` names, else the first.
    public var activeEngine: VoiceEngine? {
        let name = engine?.trimmingCharacters(in: .whitespacesAndNewlines)
        return engines.first { $0.name == name } ?? engines.first
    }
}

/// An engine that doesn't decode is skipped.
private struct LenientVoiceEngine: Decodable {
    let value: VoiceEngine?

    init(from decoder: Decoder) throws {
        value = try? VoiceEngine(from: decoder)
    }
}
