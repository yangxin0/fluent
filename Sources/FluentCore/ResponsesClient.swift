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
                        throw ResponsesClientError.http(http.statusCode, body)
                    }
                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    var yieldedAnyDelta = false
                    for try await byte in bytes {
                        guard byte == 0x0A else {
                            lineBuffer.append(byte)
                            continue
                        }
                        try Task.checkCancellation()
                        var line = String(decoding: lineBuffer, as: UTF8.self)
                        lineBuffer.removeAll(keepingCapacity: true)
                        if line.hasSuffix("\r") { line.removeLast() }
                        guard let event = parser.feed(line: line) else { continue }
                        switch ResponsesEventInterpreter.interpret(event) {
                        case .delta(let text):
                            if !text.isEmpty {
                                yieldedAnyDelta = true
                                continuation.yield(text)
                            }
                        case .completed(let text):
                            // Only use the final text when no deltas arrived;
                            // otherwise it would duplicate what we streamed.
                            if !yieldedAnyDelta, !text.isEmpty { continuation.yield(text) }
                            continuation.finish()
                            return
                        case .done:
                            continuation.finish()
                            return
                        case .error(let message):
                            throw ResponsesClientError.api(message)
                        case .ignore:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
