import XCTest
@testable import FluentCore

final class VoiceSettingsTests: XCTestCase {
    private func decode(_ voice: String) throws -> VoiceSettings {
        let json = #"{"baseURL":"u","apiKey":"k","model":"m","voice":"# + voice + "}"
        return try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8)).voice
    }

    func testDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"baseURL":"u","apiKey":"k","model":"m"}"#.utf8))
        XCTAssertEqual(config.voice, VoiceSettings())
        XCTAssertEqual(config.voice.holdKey, .rightOption)
        XCTAssertEqual(config.voice.afterSpeaking, .insert)
        XCTAssertTrue(config.voice.hotwords)
        XCTAssertNil(config.voice.toggleKey)
        XCTAssertNil(config.voice.activeEngine)
    }

    func testEnginesAndChoices() throws {
        let voice = try decode("""
        {"engines":[{"name":"Old","appId":"1","accessToken":"t"},
                    {"name":"Doubao","type":"Volcengine","apiKey":" k ","resourceId":"volc.bigasr.sauc.concurrent"}],
         "engine":"Doubao","holdKey":"Right-Command","toggleKey":"Control-Option-V",
         "afterSpeaking":"improve","hotwords":false}
        """)
        XCTAssertEqual(voice.engines.count, 2)
        XCTAssertEqual(voice.activeEngine?.name, "Doubao")
        XCTAssertEqual(voice.activeEngine?.apiKey, "k")
        XCTAssertEqual(voice.activeEngine?.resourceId, "volc.bigasr.sauc.concurrent")
        XCTAssertEqual(voice.engines[0].resourceId, VoiceEngine.defaultResourceId)
        XCTAssertTrue(voice.engines[0].isConfigured)  // the old console's pair
        XCTAssertEqual(voice.holdKey, .rightCommand)
        XCTAssertEqual(voice.toggleKey, "ctrl-opt-v")
        XCTAssertEqual(voice.afterSpeaking, .improve)
        XCTAssertFalse(voice.hotwords)
    }

    func testTheFirstEngineWithoutAMatch() throws {
        let voice = try decode(#"{"engines":[{"name":"A","apiKey":"k"},{"name":"B","apiKey":"k"}],"engine":"C"}"#)
        XCTAssertEqual(voice.activeEngine?.name, "A")
    }

    func testWrongTypesReadAsDefaults() throws {
        let voice = try decode(#"{"engines":[1,{"name":"x","type":"whisper","apiKey":"k"}],"holdKey":"shift","toggleKey":"v","afterSpeaking":3,"hotwords":"no"}"#)
        XCTAssertEqual(voice.engines.count, 1)
        XCTAssertNil(voice.engines[0].kind)  // a type this version doesn't know
        XCTAssertFalse(voice.engines[0].isConfigured)
        XCTAssertEqual(voice.holdKey, .rightOption)
        XCTAssertNil(voice.toggleKey)  // no Control, Option or Command
        XCTAssertEqual(voice.afterSpeaking, .insert)
        XCTAssertTrue(voice.hotwords)
    }

    func testAVoiceThatIsNotAnObject() throws {
        XCTAssertEqual(try decode(#""on""#), VoiceSettings())
    }
}

final class VolcengineFrameTests: XCTestCase {
    func testClientFrames() {
        let request = VolcengineFrame.fullClientRequest(Data("{}".utf8))
        XCTAssertEqual([UInt8](request), [0x11, 0x10, 0x10, 0x00, 0, 0, 0, 2, 0x7B, 0x7D])
        XCTAssertEqual([UInt8](VolcengineFrame.audio(Data([1, 2, 3]), last: false)),
                       [0x11, 0x20, 0x00, 0x00, 0, 0, 0, 3, 1, 2, 3])
        XCTAssertEqual([UInt8](VolcengineFrame.audio(Data(), last: true)), [0x11, 0x22, 0x00, 0x00, 0, 0, 0, 0])
    }

    private func response(flags: UInt8, sequence: Int32?, json: String, compression: UInt8 = 0) -> Data {
        var data = Data([0x11, 0x90 | flags, 0x10 | compression, 0x00])
        if let sequence { data.append(bigEndian: UInt32(bitPattern: sequence)) }
        let body = Data(json.utf8)
        data.append(bigEndian: UInt32(body.count))
        data.append(body)
        return data
    }

    func testServerResponses() throws {
        let partial = try VolcengineFrame.parse(response(flags: 0b0001, sequence: 2, json: #"{"result":{"text":"你好"}}"#))
        guard case .response(let last, let payload) = partial else { return XCTFail() }
        XCTAssertFalse(last)
        XCTAssertEqual(VolcengineFrame.text(of: payload), "你好")

        let final = try VolcengineFrame.parse(response(flags: 0b0011, sequence: -3, json: #"{"result":[{"text":"你好。"}]}"#))
        guard case .response(true, let finalPayload) = final else { return XCTFail() }
        XCTAssertEqual(VolcengineFrame.text(of: finalPayload), "你好。")

        let bare = try VolcengineFrame.parse(response(flags: 0, sequence: nil, json: #"{"audio_info":{}}"#))
        guard case .response(false, let barePayload) = bare else { return XCTFail() }
        XCTAssertNil(VolcengineFrame.text(of: barePayload))
    }

    func testGzipReply() throws {
        // `printf '{"result":{"text":"ok"}}' | gzip -n`
        let gz: [UInt8] = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xab, 0x56, 0x2a, 0x4a, 0x2d, 0x2e, 0xcd, 0x29, 0x51, 0xb2, 0xaa, 0x56, 0x2a, 0x49, 0xad, 0x00, 0xd2, 0x4a, 0xf9, 0xd9, 0x4a, 0xb5, 0xb5, 0x00, 0xcf, 0x54, 0xcc, 0x06, 0x18, 0x00, 0x00, 0x00]
        var frame = Data([0x11, 0x91, 0x11, 0x00, 0, 0, 0, 1])
        frame.append(bigEndian: UInt32(gz.count))
        frame.append(contentsOf: gz)
        guard case .response(_, let payload) = try VolcengineFrame.parse(frame) else { return XCTFail() }
        XCTAssertEqual(VolcengineFrame.text(of: payload), "ok")
    }

    func testErrorFrame() throws {
        var frame = Data([0x11, 0xF0, 0x10, 0x00])
        frame.append(bigEndian: 45000002)
        frame.append(bigEndian: 11)
        frame.append(Data("empty audio".utf8))
        XCTAssertEqual(try VolcengineFrame.parse(frame), .error(code: 45000002, message: "empty audio"))
    }

    func testTruncatedFrames() {
        XCTAssertThrowsError(try VolcengineFrame.parse(Data([0x11, 0x91])))
        XCTAssertThrowsError(try VolcengineFrame.parse(Data([0x11, 0x91, 0x10, 0x00, 0, 0, 0, 1, 0, 0, 0, 9, 1])))
    }

    func testRequestJSON() throws {
        let json = try JSONSerialization.jsonObject(with: VolcengineFrame.requestJSON(hotwords: ["mac", "wezterm"])) as! [String: Any]
        let audio = json["audio"] as! [String: Any]
        XCTAssertEqual(audio["format"] as? String, "pcm")
        XCTAssertEqual(audio["rate"] as? Int, 16000)
        let request = json["request"] as! [String: Any]
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_nonstream"] as? Bool, true)
        let context = (request["corpus"] as! [String: Any])["context"] as! String
        let words = try JSONSerialization.jsonObject(with: Data(context.utf8)) as! [String: [[String: String]]]
        XCTAssertEqual(words["hotwords"]?.map { $0["word"] }, ["mac", "wezterm"])

        let plain = try JSONSerialization.jsonObject(with: VolcengineFrame.requestJSON(hotwords: [])) as! [String: Any]
        XCTAssertNil((plain["request"] as! [String: Any])["corpus"])
    }

    func testHeaders() {
        let key = VolcengineRecognizer.headers(for: VoiceEngine(apiKey: "k"), connectID: "id")
        XCTAssertEqual(key["X-Api-Key"], "k")
        XCTAssertNil(key["X-Api-App-Key"])
        XCTAssertEqual(key["X-Api-Resource-Id"], VoiceEngine.defaultResourceId)
        XCTAssertEqual(key["X-Api-Connect-Id"], "id")
        let pair = VolcengineRecognizer.headers(for: VoiceEngine(appId: "1", accessToken: "t"), connectID: "id")
        XCTAssertEqual(pair["X-Api-App-Key"], "1")
        XCTAssertEqual(pair["X-Api-Access-Key"], "t")
        XCTAssertNil(pair["X-Api-Key"])
    }
}
