import Foundation

/// Edits one top-level key of a JSON object as text, so the rest of the file
/// keeps its order, spacing and number formatting (`9.7` stays `9.7`):
/// a setting changed from the IME menu or Settings touches only its line.
public enum JSONEdit {
    /// `text` with the top-level `key` set to `value`, inserted after the
    /// last key if missing, or removed when `value` is nil. Nil when `text`
    /// is not a JSON object or `value` can't be written as JSON.
    public static func setting(_ key: String, to value: Any?, in text: String) -> String? {
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) is [String: Any],
              let members = members(of: text)
        else { return nil }
        let chars = Array(text)
        let index = members.list.firstIndex { $0.key == key }

        guard let value else {
            guard let index else { return text }
            let member = members.list[index]
            let removed: Range<Int>
            if index > 0 {
                removed = members.list[index - 1].valueEnd..<member.valueEnd  // `, "key": value`
            } else if members.list.count > 1 {
                removed = member.keyStart..<members.list[1].keyStart  // `"key": value, `
            } else {
                removed = members.open + 1..<members.close
            }
            return String(chars[..<removed.lowerBound]) + String(chars[removed.upperBound...])
        }
        guard let encoded = encode(value) else { return nil }

        if let index {
            let member = members.list[index]
            return String(chars[..<member.valueStart]) + encoded + String(chars[member.valueEnd...])
        }
        let entry = (encode(key) ?? "\"\(key)\"") + ": " + encoded
        guard let last = members.list.last else {
            return String(chars[...members.open]) + "\n  " + entry + "\n" + String(chars[members.close...])
        }
        // Indented like the first key: the whitespace before it.
        let indent = String(chars[members.open + 1..<members.list[0].keyStart])
        return String(chars[..<last.valueEnd]) + "," + (indent.isEmpty ? " " : indent) + entry
            + String(chars[last.valueEnd...])
    }

    /// JSON for `value`: strings escaped, numbers as Swift prints them (the
    /// shortest form that reads back the same), arrays on one line.
    static func encode(_ value: Any) -> String? {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            guard let data = try? JSONSerialization.data(withJSONObject: string,
                                                         options: [.fragmentsAllowed, .withoutEscapingSlashes])
            else { return nil }
            return String(decoding: data, as: UTF8.self)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            if double == double.rounded(), abs(double) < 1e15 { return String(Int64(double)) }
            return "\(double)"
        case let array as [Any]:
            let items = array.map(encode)
            guard !items.contains(where: { $0 == nil }) else { return nil }
            return "[" + items.map { $0! }.joined(separator: ", ") + "]"
        case let object as [String: Any]:
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object,
                                                         options: [.sortedKeys, .withoutEscapingSlashes])
            else { return nil }
            return String(decoding: data, as: UTF8.self)
        default:
            return nil
        }
    }

    private struct Member {
        var key: String
        var keyStart: Int
        var valueStart: Int
        var valueEnd: Int
    }

    /// The top-level members with their character offsets, for text already
    /// known to be a valid JSON object.
    private static func members(of text: String) -> (open: Int, close: Int, list: [Member])? {
        let chars = Array(text)
        var i = 0
        func skipSpace() { while i < chars.count, chars[i].isWhitespace { i += 1 } }
        func skipString() {
            i += 1  // opening quote
            while i < chars.count, chars[i] != "\"" { i += chars[i] == "\\" ? 2 : 1 }
            i += 1
        }
        func skipValue() {
            if chars[i] == "\"" { return skipString() }
            if chars[i] == "{" || chars[i] == "[" {
                var depth = 0
                repeat {
                    switch chars[i] {
                    case "\"": skipString(); continue
                    case "{", "[": depth += 1
                    case "}", "]": depth -= 1
                    default: break
                    }
                    i += 1
                } while depth > 0 && i < chars.count
                return
            }
            while i < chars.count, !chars[i].isWhitespace, !",}]".contains(chars[i]) { i += 1 }  // number, literal
        }

        skipSpace()
        guard i < chars.count, chars[i] == "{" else { return nil }
        let open = i
        i += 1
        var list: [Member] = []
        while true {
            skipSpace()
            guard i < chars.count else { return nil }
            if chars[i] == "}" { return (open, i, list) }
            if chars[i] == "," { i += 1; continue }
            let keyStart = i
            skipString()
            let literal = String(chars[keyStart..<i])
            guard let key = (try? JSONSerialization.jsonObject(with: Data(literal.utf8),
                                                               options: .fragmentsAllowed)) as? String
            else { return nil }
            skipSpace()
            i += 1  // colon
            skipSpace()
            let valueStart = i
            skipValue()
            list.append(Member(key: key, keyStart: keyStart, valueStart: valueStart, valueEnd: i))
        }
    }
}
