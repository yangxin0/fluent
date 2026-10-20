import XCTest
@testable import FluentCore

final class AppConfigTests: XCTestCase {
    func testDecodeWithDefaults() throws {
        let json = #"{"baseURL":"https://api.openai.com/v1","apiKey":"sk-x","model":"gpt-4o-mini"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.debounceMs, 350)
        XCTAssertEqual(config.timeoutSeconds, 10)
        XCTAssertTrue(config.isConfigured)
    }

    func testToggleNoticePreference() throws {
        let base = #""baseURL":"u","apiKey":"k","model":"m""#
        func pref(_ json: String) throws -> String {
            try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).toggleNoticePreference
        }
        XCTAssertEqual(try pref("{\(base)}"), "badge")
        XCTAssertEqual(try pref("{\(base),\"toggleNotice\":\"Pill\"}"), "pill")
        XCTAssertEqual(try pref("{\(base),\"toggleNotice\":\"bubble\"}"), "bubble")
        XCTAssertEqual(try pref("{\(base),\"toggleNotice\":\"keys\"}"), "keys")
        XCTAssertEqual(try pref("{\(base),\"toggleNotice\":\"nonsense\"}"), "badge")
        XCTAssertEqual(try pref("{\(base),\"toggleNotice\":2}"), "badge")
    }

    func testAppearancePreferenceNormalization() throws {
        func pref(_ json: String) throws -> String {
            try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).appearancePreference
        }
        let base = #""baseURL":"https://x/v1","apiKey":"sk-x","model":"m""#
        XCTAssertEqual(try pref("{\(base)}"), "auto")
        XCTAssertEqual(try pref("{\(base),\"appearance\":\"AUTO\"}"), "auto")
        XCTAssertEqual(try pref("{\(base),\"appearance\":\"Light\"}"), "light")
        XCTAssertEqual(try pref("{\(base),\"appearance\":\"dark\"}"), "dark")
        XCTAssertEqual(try pref("{\(base),\"appearance\":\"nonsense\"}"), "auto")
    }

    func testCandidateBarSettings() throws {
        func decode(_ extra: String) throws -> AppConfig {
            try JSONDecoder().decode(AppConfig.self, from: Data(#"{"baseURL":"u","apiKey":"k","model":"m"\#(extra)}"#.utf8))
        }
        let plain = try decode("")
        XCTAssertEqual(plain.candidateBarSizePreference, "medium")
        XCTAssertEqual(plain.candidateTextSizeValue, 18)
        XCTAssertEqual(plain.candidatePageSizeValue, 6)
        let set = try decode(#","candidateBarSize":"Large","candidateTextSize":22.5,"candidatePageSize":8"#)
        XCTAssertEqual(set.candidateBarSizePreference, "large")
        XCTAssertEqual(set.candidateTextSizeValue, 22.5)
        XCTAssertEqual(set.candidatePageSizeValue, 8)
        let clamped = try decode(#","candidateBarSize":"huge","candidateTextSize":3,"candidatePageSize":12.4"#)
        XCTAssertEqual(clamped.candidateBarSizePreference, "medium")
        XCTAssertEqual(clamped.candidateTextSizeValue, 14)
        XCTAssertEqual(clamped.candidatePageSizeValue, 9)
        XCTAssertEqual(try decode(#","candidateTextSize":99,"candidatePageSize":4.6"#).candidateTextSizeValue, 28)
        XCTAssertEqual(try decode(#","candidatePageSize":4.6"#).candidatePageSizeValue, 5)
        // A wrong type leaves the default.
        let wrong = try decode(#","candidateBarSize":2,"candidateTextSize":"big","candidatePageSize":[7]"#)
        XCTAssertEqual(wrong.candidateBarSizePreference, "medium")
        XCTAssertEqual(wrong.candidateTextSizeValue, 18)
        XCTAssertEqual(wrong.candidatePageSizeValue, 6)
    }

    func testTerminalModeNormalization() throws {
        func pref(_ json: String) throws -> String {
            try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).terminalModePreference
        }
        let base = #""baseURL":"https://x/v1","apiKey":"sk-x","model":"m""#
        XCTAssertEqual(try pref("{\(base)}"), "auto")
        XCTAssertEqual(try pref("{\(base),\"terminalMode\":\"Always\"}"), "always")
        XCTAssertEqual(try pref("{\(base),\"terminalMode\":\"never\"}"), "never")
        XCTAssertEqual(try pref("{\(base),\"terminalMode\":\"nonsense\"}"), "auto")
    }

    func testChinesePreference() throws {
        func decode(_ extra: String) throws -> AppConfig {
            try JSONDecoder().decode(AppConfig.self, from: Data(#"{"baseURL":"https://x/v1","apiKey":"sk-x","model":"m"\#(extra)}"#.utf8))
        }
        XCTAssertEqual(try decode("").chinesePreference, "pinyin")
        XCTAssertEqual(try decode(#","chinese":"Pinyin""#).chinesePreference, "pinyin")
        XCTAssertEqual(try decode(#","chinese":"quanpin""#).chinesePreference, "pinyin")
        XCTAssertEqual(try decode(#","chinese":"Xiaohe""#).chinesePreference, "xiaohe")
        XCTAssertEqual(try decode(#","chinese":"off""#).chinesePreference, "off")
        XCTAssertEqual(try decode(#","chinese":"nonsense""#).chinesePreference, "pinyin")
        let full = try decode(#","chinese":"pinyin","pinyinAbbreviations":false,"fuzzyPinyin":["zh=z"]"#)
        XCTAssertEqual(full.pinyinAbbreviations, false)
        XCTAssertEqual(full.fuzzyPinyin, ["zh=z"])
    }

    func testSetKeepsTheOtherKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(configURL: dir.appendingPathComponent("config.json"))
        XCTAssertTrue(store.writeTemplateIfMissing())
        XCTAssertTrue(store.set("chinese", to: "pinyin"))
        let config = try XCTUnwrap(store.current())
        XCTAssertEqual(config.chinesePreference, "pinyin")
        XCTAssertEqual(config.model, "gpt-4o-mini")
        XCTAssertEqual(config.apiKey, AppConfig.placeholderKey)
    }

    func testNumericFieldsAreClamped() throws {
        func decode(_ extra: String) throws -> AppConfig {
            let json = #"{"baseURL":"https://x/v1","apiKey":"sk-x","model":"m","# + extra + "}"
            return try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        }
        // Would overflow the nanosecond multiply in RewriteEngine if passed through.
        XCTAssertEqual(try decode(#""debounceMs":9223372036854775807"#).debounceMs,
                       AppConfig.debounceMsRange.upperBound)
        XCTAssertEqual(try decode(#""debounceMs":-5"#).debounceMs, 0)
        XCTAssertEqual(try decode(#""debounceMs":200"#).debounceMs, 200)
        XCTAssertEqual(try decode(#""timeoutSeconds":0"#).timeoutSeconds,
                       AppConfig.timeoutSecondsRange.lowerBound)
        XCTAssertEqual(try decode(#""timeoutSeconds":-3"#).timeoutSeconds,
                       AppConfig.timeoutSecondsRange.lowerBound)
        XCTAssertEqual(try decode(#""timeoutSeconds":1e300"#).timeoutSeconds,
                       AppConfig.timeoutSecondsRange.upperBound)
        XCTAssertEqual(try decode(#""timeoutSeconds":2.5"#).timeoutSeconds, 2.5)
        // The memberwise initializer clamps too, including non-finite doubles.
        XCTAssertEqual(AppConfig(baseURL: "u", apiKey: "k", model: "m", timeoutSeconds: .nan).timeoutSeconds,
                       AppConfig.defaultTimeoutSeconds)
        XCTAssertEqual(AppConfig(baseURL: "u", apiKey: "k", model: "m", debounceMs: .max).debounceMs,
                       AppConfig.debounceMsRange.upperBound)
    }

    func testPlaceholderKeyIsNotConfigured() throws {
        let json = #"{"baseURL":"https://api.openai.com/v1","apiKey":"sk-REPLACE_ME","model":"m"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.isConfigured)
    }

    func testRequestBuilding() throws {
        let config = AppConfig(baseURL: "https://example.com/v1/", apiKey: "k", model: "m")
        let request = try ResponsesClient.makeRequest(config: config, instructions: "inst", input: "hi")
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let body = try XCTUnwrap(request.httpBody)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "m")
        // The instructions go right before the text, with no system prompt.
        XCTAssertEqual(obj["input"] as? String, "inst\n\nhi")
        XCTAssertNil(obj["instructions"])
        XCTAssertEqual(obj["stream"] as? Bool, true)
        XCTAssertNil(request.value(forHTTPHeaderField: "originator"))
    }

    func testCodexHeadersOnlyForGPTModels() throws {
        let gpt = try ResponsesClient.makeRequest(
            config: AppConfig(baseURL: "https://example.com/v1", apiKey: "k", model: "gpt-5.6-luna"),
            instructions: "inst", input: "hi")
        XCTAssertEqual(gpt.value(forHTTPHeaderField: "originator"), "codex_cli_rs")
        XCTAssertEqual(gpt.value(forHTTPHeaderField: "User-Agent"), "codex_cli_rs/0.152.1")
        let deepseek = try ResponsesClient.makeRequest(
            config: AppConfig(baseURL: "https://example.com", apiKey: "k", model: "deepseek-v4-flash",
                              reasoningEffort: "none"),
            instructions: "inst", input: "hi")
        XCTAssertNil(deepseek.value(forHTTPHeaderField: "originator"))
        XCTAssertNil(deepseek.value(forHTTPHeaderField: "User-Agent"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(deepseek.httpBody)) as? [String: Any])
        XCTAssertEqual((obj["reasoning"] as? [String: String])?["effort"], "none")
    }

    func testChatRequestBuilding() throws {
        let config = AppConfig(providers: [
            Provider(name: "DeepSeek", api: .chat, baseURL: "https://api.deepseek.com/", apiKey: "k",
                     model: "deepseek-chat", reasoningEffort: "low"),
        ])
        let request = try ResponsesClient.makeRequest(config: config, instructions: "inst", input: "hi")
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertNil(request.value(forHTTPHeaderField: "originator"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "deepseek-chat")
        XCTAssertEqual(obj["stream"] as? Bool, true)
        XCTAssertEqual(obj["reasoning_effort"] as? String, "low")
        XCTAssertNil(obj["input"])
        XCTAssertEqual(obj["messages"] as? [[String: String]], [["role": "user", "content": "inst\n\nhi"]])
        // A GPT model behind a chat API is not a Codex client.
        let gpt = AppConfig(providers: [Provider(api: .chat, baseURL: "https://x/v1", apiKey: "k", model: "gpt-5")])
        XCTAssertNil(try ResponsesClient.makeRequest(config: gpt, instructions: "i", input: "hi")
            .value(forHTTPHeaderField: "originator"))
    }

    func testProvidersReplaceTheTopLevelEndpoint() throws {
        let json = #"""
        {
          "providers": [
            "not a provider",
            {"name": " Work ", "baseURL": "https://work/v1", "apiKey": "sk-REPLACE_ME", "model": "gpt-5-mini"},
            {"name": "DeepSeek", "api": "Chat", "baseURL": "https://api.deepseek.com", "apiKey": " sk-1\n",
             "model": "deepseek-chat", "reasoningEffort": "low"},
            {"name": 7, "api": "smoke signals", "baseURL": ["x"]}
          ],
          "provider": "DeepSeek",
          "prompts": {"polish": "Make it friendly.", "fix": 3}
        }
        """#
        var config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.providers.map(\.name), ["Work", "DeepSeek", ""])
        XCTAssertEqual(config.providers.map(\.api), [.responses, .chat, .responses])
        XCTAssertEqual(config.providers[2].baseURL, "")
        XCTAssertEqual(config.activeProviderIndex, 1)
        XCTAssertEqual(config.activeProvider.apiKey, "sk-1")
        XCTAssertEqual(config.activeProvider.reasoningEffort, "low")
        XCTAssertTrue(config.isConfigured)
        XCTAssertEqual(config.prompts, ["polish": "Make it friendly."])

        config.provider = "Work"  // a placeholder key
        XCTAssertFalse(config.isConfigured)
        config.provider = "Nobody"  // the first, then
        XCTAssertEqual(config.activeProviderIndex, 0)
        config.provider = nil
        XCTAssertEqual(config.activeProvider.name, "Work")
    }

    func testTheTopLevelEndpointServesUntilThereAreProviders() throws {
        let legacy = try JSONDecoder().decode(AppConfig.self, from: Data(
            #"{"baseURL":"https://x/v1","apiKey":"sk-1","model":"m","providers":"OpenAI","prompts":[1]}"#.utf8))
        XCTAssertNil(legacy.activeProviderIndex)
        XCTAssertEqual(legacy.activeProvider, Provider(baseURL: "https://x/v1", apiKey: "sk-1", model: "m"))
        XCTAssertEqual(legacy.prompts, [:])
        XCTAssertTrue(legacy.isConfigured)
        // An empty list (or one with no objects) is no list: the top-level
        // keys are required again.
        XCTAssertThrowsError(try JSONDecoder().decode(AppConfig.self, from: Data(#"{"providers":[1]}"#.utf8)))
    }

    func testLegacyConfigIsCopiedOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = dir.appendingPathComponent("english-input/config.json")
        let url = dir.appendingPathComponent("fluent/config.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old".write(to: legacy, atomically: true, encoding: .utf8)
        ConfigStore.migrate(from: legacy, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        try "new".write(to: url, atomically: true, encoding: .utf8)
        ConfigStore.migrate(from: legacy, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
    }

    func testTemplateWriteAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ei-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: url)
        XCTAssertNil(store.current())
        XCTAssertTrue(store.writeTemplateIfMissing())
        let config = try XCTUnwrap(store.current())
        XCTAssertFalse(config.isConfigured)
        try? FileManager.default.removeItem(at: dir)
    }

    private func temporaryStore() -> (ConfigStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString)")
        return (ConfigStore(configURL: dir.appendingPathComponent("config.json")), dir)
    }

    func testAWrongTypeOnlyUnsetsThatKey() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("""
        {"baseURL":"https://x","apiKey":"sk-1","model":"m","debounceMs":350.4,
         "terminalApps":"com.x","pinyinAbbreviations":"false","chinese":"off"}
        """.utf8))
        XCTAssertEqual(config.debounceMs, 350)
        XCTAssertNil(config.terminalApps)
        XCTAssertNil(config.pinyinAbbreviations)
        XCTAssertEqual(config.chinesePreference, "off")  // the rest still applies
    }

    func testPastedWhitespaceIsTrimmed() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"""
        {"baseURL":" https://x/v1 ","apiKey":"sk-1\n","model":"m "}
        """#.utf8))
        XCTAssertEqual(config.baseURL, "https://x/v1")
        XCTAssertEqual(config.apiKey, "sk-1")
        XCTAssertEqual(config.model, "m")
    }

    func testProblemSaysWhyTheConfigIsUnusable() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"baseURL":"https://x","model":"m"}"#.write(to: store.configURL, atomically: false, encoding: .utf8)
        XCTAssertNil(store.current())
        XCTAssertEqual(store.problem, #""apiKey" is missing"#)
        try #"{"baseURL":"#.write(to: store.configURL, atomically: false, encoding: .utf8)
        store.invalidate()
        XCTAssertNil(store.current())
        XCTAssertEqual(store.problem, "not valid JSON")
    }

    func testTheKeyFileIsPrivate() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        func mode(_ path: String) throws -> Int {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
        }
        XCTAssertTrue(store.writeTemplateIfMissing())
        XCTAssertEqual(try mode(store.configURL.path), 0o600)
        XCTAssertEqual(try mode(dir.path), 0o700)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.configURL.path)
        store.invalidate()
        _ = store.current()
        XCTAssertEqual(try mode(store.configURL.path), 0o600)  // tightened on load
    }

    func testSetWritesThroughASymlink() throws {
        let (store, dir) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("dotfiles/fluent.json")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"baseURL":"https://x","apiKey":"sk-1","model":"m"}"#.write(to: target, atomically: false, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: store.configURL, withDestinationURL: target)
        XCTAssertTrue(store.set("chinese", to: "pinyin"))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: store.configURL.path), target.path)
        XCTAssertEqual(store.current()?.chinesePreference, "pinyin")
        // An edit to the target is noticed through the link.
        try #"{"baseURL":"https://x","apiKey":"sk-1","model":"m2"}"#.write(to: target, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: target.path)
        XCTAssertEqual(store.current()?.model, "m2")
    }
}
