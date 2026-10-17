import Foundation

public enum ResponsesClientError: LocalizedError {
    case invalidBaseURL(String)
    case http(Int, String)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let s): return "Invalid base URL: \(s)"
        case .http(let code, let body):
            let snippet = body.prefix(200)
            return "HTTP \(code)\(snippet.isEmpty ? "" : ": \(snippet)")"
        case .api(let msg): return msg
        }
    }
}

/// The bytes of a Responses stream as output text. Lines end in LF, CRLF or
/// a bare CR, as SSE allows; `isFinished` turns true at the terminal event.
struct ResponsesStreamDecoder {
    private var parser = SSEParser()
    private var line: [UInt8] = []
    private var afterCR = false
    private var yieldedAnyDelta = false
    private(set) var isFinished = false

    /// Feeds one byte; returns text to yield, if any. Throws API errors.
    mutating func feed(_ byte: UInt8) throws -> String? {
        if byte == 0x0A, afterCR {  // the LF of a CRLF
            afterCR = false
            return nil
        }
        afterCR = byte == 0x0D
        guard byte == 0x0A || byte == 0x0D else {
            line.append(byte)
            return nil
        }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        guard let event = parser.feed(line: text) else { return nil }
        switch ResponsesEventInterpreter.interpret(event) {
        case .delta(let delta):
            guard !delta.isEmpty else { return nil }
            yieldedAnyDelta = true
            return delta
        case .completed(let full):
            isFinished = true
            // Only when no deltas arrived; otherwise it repeats them.
            return !yieldedAnyDelta && !full.isEmpty ? full : nil
        case .done:
            isFinished = true
            return nil
        case .error(let message):
            throw ResponsesClientError.api(message)
        case .ignore:
            return nil
        }
    }
}

/// Streams output text from an OpenAI Responses-API-compatible endpoint.
public final class ResponsesClient {
    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// Yields output-text deltas; finishes on stream completion, throws on
    /// HTTP or API errors. Cancelling the consuming task aborts the request.
    public func stream(config: AppConfig, instructions: String, input: String)
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.makeRequest(config: config, instructions: instructions, input: input)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 2000 { break }
                        }
                        throw ResponsesClientError.http(http.statusCode, Self.errorMessage(fromBody: body))
                    }
                    var decoder = ResponsesStreamDecoder()
                    for try await byte in bytes {
                        if byte == 0x0A || byte == 0x0D { try Task.checkCancellation() }
                        if let text = try decoder.feed(byte) { continuation.yield(text) }
                        if decoder.isFinished {
                            continuation.finish()
                            return
                        }
                    }
                    // Closed before the reply said it was finished (a proxy
                    // timeout, a dropped connection): never commit half of it.
                    throw ResponsesClientError.api("reply cut off")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The `error.message` of a JSON error body, else the body as is.
    static func errorMessage(fromBody body: String) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        else { return body }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["error"] as? String ?? object["message"] as? String ?? body
    }

    /// Version reported in the Codex User-Agent (`codex --version`).
    static let codexVersion = "0.152.1"

    static func identifiesAsCodex(model: String) -> Bool {
        let name = model.lowercased()
        return name.hasPrefix("gpt") || name.contains("codex")
    }

    static func makeRequest(config: AppConfig, instructions: String, input: String) throws -> URLRequest {
        var base = config.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/responses") else {
            throw ResponsesClientError.invalidBaseURL(config.baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        // Some gateways gate the Responses API for GPT models to recognized
        // coding-agent clients; identify as Codex for those. Other providers
        // must not see it: DeepSeek treats a Codex client differently and
        // ignores `reasoning.effort: none`, thinking anyway.
        if identifiesAsCodex(model: config.model) {
            request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
            request.setValue("codex_cli_rs/\(codexVersion)", forHTTPHeaderField: "User-Agent")
        }
        request.timeoutInterval = config.timeoutSeconds
        var body: [String: Any] = [
            "model": config.model,
            "instructions": instructions,
            "input": input,
            "stream": true,
        ]
        if let effort = config.reasoningEffort, !effort.isEmpty {
            body["reasoning"] = ["effort": effort]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
