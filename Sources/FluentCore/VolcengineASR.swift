import Foundation

/// The binary framing of 豆包流式语音识别 over WebSocket: a 4-byte header
/// (version and header size, message type and flags, serialization and
/// compression, reserved), then big-endian sizes and the payload. Fluent
/// sends JSON and raw PCM uncompressed, and the server answers the same way.
public enum VolcengineFrame {
    /// The first message: the request parameters as JSON.
    public static func fullClientRequest(_ json: Data) -> Data {
        frame(header: [0x11, 0x10, 0x10, 0x00], payload: json)
    }

    /// Audio: 16 kHz, 16-bit little-endian mono PCM. The last packet (`last`)
    /// asks for the final result.
    public static func audio(_ pcm: Data, last: Bool) -> Data {
        frame(header: [0x11, last ? 0x22 : 0x20, 0x00, 0x00], payload: pcm)
    }

    private static func frame(header: [UInt8], payload: Data) -> Data {
        var data = Data(header)
        data.append(bigEndian: UInt32(payload.count))
        data.append(payload)
        return data
    }

    public enum Message: Equatable {
        /// A recognition result; `last` once the final one arrives.
        case response(last: Bool, payload: Data)
        case error(code: UInt32, message: String)
    }

    public enum ParseError: Error, Equatable {
        case truncated
        case unknownType(UInt8)
        case compressed
    }

    public static func parse(_ data: Data) throws -> Message {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw ParseError.truncated }
        var at = Int(bytes[0] & 0x0F) * 4
        let type = bytes[1] >> 4
        let flags = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        func word() throws -> UInt32 {
            guard at + 4 <= bytes.count else { throw ParseError.truncated }
            defer { at += 4 }
            return bytes[at..<at + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func payload(_ size: UInt32) throws -> Data {
            guard at + Int(size) <= bytes.count else { throw ParseError.truncated }
            let body = Data(bytes[at..<at + Int(size)])
            guard compression == 0 else {
                guard compression == 1, let plain = gunzip(body) else { throw ParseError.compressed }
                return plain
            }
            return body
        }
        switch type {
        case 0b1001:
            if flags & 0b0001 != 0 { _ = try word() }  // the sequence number
            let size = try word()
            return .response(last: flags & 0b0010 != 0, payload: try payload(size))
        case 0b1111:
            let code = try word()
            let size = try word()
            guard at + Int(size) <= bytes.count else { throw ParseError.truncated }
            let message = String(decoding: bytes[at..<at + Int(size)], as: UTF8.self)
            return .error(code: code, message: message)
        default:
            throw ParseError.unknownType(type)
        }
    }

    /// A gzip member's data: its header skipped, the raw deflate inflated.
    static func gunzip(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var at = 10
        if flags & 0x04 != 0, at + 2 <= b.count { at += 2 + (Int(b[at]) | Int(b[at + 1]) << 8) }  // extra
        if flags & 0x08 != 0 { while at < b.count, b[at] != 0 { at += 1 }; at += 1 }  // name
        if flags & 0x10 != 0 { while at < b.count, b[at] != 0 { at += 1 }; at += 1 }  // comment
        if flags & 0x02 != 0 { at += 2 }  // header crc
        guard at < b.count - 8 else { return nil }
        return try? (Data(b[at..<b.count - 8]) as NSData).decompressed(using: .zlib) as Data
    }

    /// The text of a result payload: `result.text`, or the first result's
    /// when `result` is a list.
    public static func text(of payload: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        if let result = object["result"] as? [String: Any] {
            return result["text"] as? String
        }
        if let results = object["result"] as? [[String: Any]] {
            return results.first?["text"] as? String
        }
        return nil
    }

    /// The parameters of a recognition: PCM as Fluent records it, the two-pass
    /// mode (fast text while speaking, a more accurate pass per sentence),
    /// punctuation and written-out numbers, and `hotwords` to favor.
    public static func requestJSON(hotwords: [String]) -> Data {
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_nonstream": true,
            "enable_itn": true,
            "enable_punc": true,
            "result_type": "full",
        ]
        if !hotwords.isEmpty {
            let words = ["hotwords": hotwords.map { ["word": $0] }]
            if let context = try? JSONSerialization.data(withJSONObject: words),
               let string = String(data: context, encoding: .utf8) {
                request["corpus"] = ["context": string]
            }
        }
        let object: [String: Any] = [
            "user": ["uid": "fluent"],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
            "request": request,
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// The hotwords to send: the engine takes about 100 tokens on this
    /// endpoint, so at most `limit` words.
    public static func hotwords(_ words: [String], limit: Int = 60) -> [String] {
        Array(words.prefix(limit))
    }
}

extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
                            UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }
}

/// One recognition over the two-way streaming endpoint: `start`, `send`
/// audio as it comes, `finish` for the final text. Called on the main
/// queue; its state lives there, and events arrive there.
public final class VolcengineRecognizer: NSObject, URLSessionWebSocketDelegate {
    public enum Event: Equatable {
        case partial(String)
        case final(String)
        case failed(String)
    }

    public static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!

    private let engine: VoiceEngine
    private let hotwords: [String]
    private let onEvent: (Event) -> Void
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var done = false
    private var lastText = ""
    /// The server's log id, for reports: the response header X-Tt-Logid.
    public private(set) var logID: String?

    public init(engine: VoiceEngine, hotwords: [String], onEvent: @escaping (Event) -> Void) {
        self.engine = engine
        self.hotwords = hotwords
        self.onEvent = onEvent
    }

    /// The handshake's headers: the engine's credentials and a fresh id.
    public static func headers(for engine: VoiceEngine, connectID: String) -> [String: String] {
        var headers = ["X-Api-Resource-Id": engine.resourceId, "X-Api-Connect-Id": connectID,
                       "X-Api-Request-Id": connectID]
        if !engine.apiKey.isEmpty {
            headers["X-Api-Key"] = engine.apiKey
        } else {
            headers["X-Api-App-Key"] = engine.appId
            headers["X-Api-Access-Key"] = engine.accessToken
        }
        return headers
    }

    public func start() {
        var request = URLRequest(url: Self.endpoint)
        for (name, value) in Self.headers(for: engine, connectID: UUID().uuidString) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        transmit(VolcengineFrame.fullClientRequest(VolcengineFrame.requestJSON(hotwords: hotwords)))
        receive()
    }

    public func send(_ pcm: Data) {
        guard !done, !pcm.isEmpty else { return }
        transmit(VolcengineFrame.audio(pcm, last: false))
    }

    /// Sends `pcm` as the last packet; the final text follows.
    public func finish(with pcm: Data = Data()) {
        guard !done else { return }
        transmit(VolcengineFrame.audio(pcm, last: true))
    }

    private func transmit(_ frame: Data) {
        task?.send(.data(frame)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async { self?.fail(error.localizedDescription) }
        }
    }

    public func cancel() {
        done = true
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func receive() {
        task?.receive { [weak self] result in
            DispatchQueue.main.async { self?.handle(result) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        guard !done else { return }
        switch result {
        case .failure(let error):
            fail(refusal() ?? error.localizedDescription)
        case .success(.data(let data)):
            do {
                switch try VolcengineFrame.parse(data) {
                case .response(let last, let payload):
                    let text = VolcengineFrame.text(of: payload) ?? lastText
                    lastText = text
                    if last {
                        emit(.final(text))
                        close()
                        return
                    }
                    emit(.partial(text))
                case .error(let code, let message):
                    fail("\(code) \(message)")
                    return
                }
            } catch {
                fail("unreadable reply: \(error)")
                return
            }
            receive()
        case .success:
            receive()
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?) {
        let id = (webSocketTask.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Tt-Logid")
        DispatchQueue.main.async { self.logID = id }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            self.fail(self.refusal() ?? error.localizedDescription)
        }
    }

    /// A handshake the service refused (a wrong key: HTTP 401), with its
    /// log id; nil once the connection was upgraded.
    private func refusal() -> String? {
        guard let response = task?.response as? HTTPURLResponse, response.statusCode != 101 else { return nil }
        logID = logID ?? response.value(forHTTPHeaderField: "X-Tt-Logid")
        let reason = response.statusCode == 401 || response.statusCode == 403 ? ": the engine refused the key" : ""
        return "HTTP \(response.statusCode)\(reason)"
    }

    private func close() {
        done = true
        task?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    private func fail(_ message: String) {
        guard !done else { return }
        done = true
        let detail = logID.map { "\(message) (logid \($0))" } ?? message
        emit(.failed(detail))
        task?.cancel(with: .abnormalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    private func emit(_ event: Event) {
        onEvent(event)
    }
}
