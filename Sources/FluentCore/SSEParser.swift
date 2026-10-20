import Foundation

public struct SSEEvent: Equatable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental server-sent-events parser. Feed it one line at a time
/// (without the trailing newline); it emits an event at each blank line.
public struct SSEParser {
    private var eventName: String?
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(line: String) -> SSEEvent? {
        if line.isEmpty {
            guard !dataLines.isEmpty || eventName != nil else { return nil }
            let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
            eventName = nil
            dataLines = []
            return event.data.isEmpty && event.event == nil ? nil : event
        }
        if line.hasPrefix(":") { return nil } // comment
        let (field, value): (Substring, Substring)
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            var v = line[line.index(after: colon)...]
            if v.hasPrefix(" ") { v = v.dropFirst() }
            value = v
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break // id/retry/unknown ignored
        }
        return nil
    }
}

/// What an SSE event from a Responses or Chat Completions endpoint means
/// for us.
public enum ResponsesStreamItem: Equatable {
    case delta(String)
    /// A chat stream's last chunk (its `finish_reason` is set): its text, if
    /// any, ends the reply.
    case lastDelta(String)
    /// `response.output_text.done`: the stream is finished and this is the
    /// complete text. Providers that skip deltas deliver everything here.
    case completed(String)
    case done
    case error(String)
    case ignore
}

public enum ResponsesEventInterpreter {
    /// Tolerant interpretation: prefer the JSON `type` field, fall back to the
    /// SSE `event:` name, and ignore unknown lifecycle events so sparse
    /// compatible providers still work. Also accepts the chat-style `[DONE]`.
    public static func interpret(_ event: SSEEvent) -> ResponsesStreamItem {
        let data = event.data.trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" { return .done }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] else {
            return .ignore
        }
        let type = (obj["type"] as? String) ?? event.event ?? ""
        switch type {
        case "response.output_text.delta":
            return .delta(obj["delta"] as? String ?? "")
        case "response.output_text.done":
            return .completed(obj["text"] as? String ?? "")
        case "response.completed":
            return .done
        case "response.incomplete":
            // Cut short (max_output_tokens, a content filter): not a rewrite.
            let details = (obj["response"] as? [String: Any])?["incomplete_details"] as? [String: Any]
            return .error((details?["reason"] as? String).map { "reply incomplete: \($0)" } ?? "reply incomplete")
        case "response.failed", "response.error", "error":
            return .error(Self.errorMessage(obj))
        default:
            return .ignore
        }
    }

    static func errorMessage(_ obj: [String: Any]) -> String {
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        if let resp = obj["response"] as? [String: Any],
           let err = resp["error"] as? [String: Any],
           let msg = err["message"] as? String { return msg }
        return "API error"
    }
}

public enum ChatEventInterpreter {
    /// A Chat Completions stream: `choices[0].delta.content` chunks until one
    /// with a `finish_reason`, then `[DONE]`. Reasoning text
    /// (`reasoning_content`) is not part of the reply.
    public static func interpret(_ event: SSEEvent) -> ResponsesStreamItem {
        let data = event.data.trimmingCharacters(in: .whitespaces)
        if data == "[DONE]" { return .done }
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any] else {
            return .ignore
        }
        if obj["error"] != nil { return .error(ResponsesEventInterpreter.errorMessage(obj)) }
        guard let choice = (obj["choices"] as? [[String: Any]])?.first else { return .ignore }
        let content = (choice["delta"] as? [String: Any])?["content"] as? String ?? ""
        guard let reason = choice["finish_reason"] as? String else { return .delta(content) }
        switch reason {
        case "length", "content_filter":
            // Cut short: not a rewrite.
            return .error("reply incomplete: \(reason)")
        default:
            return .lastDelta(content)
        }
    }
}
