import XCTest
@testable import EnglishInputCore

final class AppConfigTests: XCTestCase {
    func testDecodeWithDefaults() throws {
        let json = #"{"baseURL":"https://api.openai.com/v1","apiKey":"sk-x","model":"gpt-4o-mini"}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.debounceMs, 350)
        XCTAssertEqual(config.timeoutSeconds, 10)
        XCTAssertTrue(config.isConfigured)
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
        XCTAssertEqual(obj["input"] as? String, "hi")
        XCTAssertEqual(obj["instructions"] as? String, "inst")
        XCTAssertEqual(obj["stream"] as? Bool, true)
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
}
