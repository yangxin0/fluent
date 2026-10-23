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
    /// What is held to talk: Fn or one side's modifier alone, or a
    /// shortcut, from its press until its key is let go.
    public enum HoldKey: Equatable {
        case off
        case fn
        case modifier(Modifier)
        case shortcut(String)

        public enum Modifier: String, CaseIterable {
            case leftControl = "left-control", rightControl = "right-control"
            case leftOption = "left-option", rightOption = "right-option"
            case leftCommand = "left-command", rightCommand = "right-command"
            case leftShift = "left-shift", rightShift = "right-shift"
        }

        /// `off`, `fn`, a modifier such as `left-command`, or a `KeyCombo`
        /// name such as `ctrl-space`; nil for anything else.
        public init?(name: String) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch name {
            case "off": self = .off
            case "fn": self = .fn
            default:
                if let modifier = Modifier(rawValue: name) {
                    self = .modifier(modifier)
                } else if let combo = KeyCombo.normalized(name) {
                    self = .shortcut(combo)
                } else {
                    return nil
                }
            }
        }

        public var name: String {
            switch self {
            case .off: "off"
            case .fn: "fn"
            case .modifier(let modifier): modifier.rawValue
            case .shortcut(let combo): combo
            }
        }
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
    public var holdKey = HoldKey.fn
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
        holdKey = optional(String.self, .holdKey).flatMap(HoldKey.init(name:)) ?? .fn
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
