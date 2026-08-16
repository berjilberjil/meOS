import Foundation

/// Turns messy model output (`{"reply":"..."}`, nested copies, ```json fences)
/// into the sentence the user should actually see.
enum ChatText {
    static func unwrap(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            if let r = s.range(of: "```") { s = String(s[..<r.lowerBound]) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for _ in 0..<5 {
            guard let next = peel(s), next != s else { break }
            s = next.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private static func peel(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") else { return nil }
        if let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reply = obj["reply"] as? String {
            return reply
        }
        // Incomplete stream: {"reply":"Hello the
        guard let key = t.range(of: "\"reply\"") else { return nil }
        var rest = t[key.upperBound...]
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        guard rest.first == ":" else { return nil }
        rest = rest.dropFirst()
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        guard rest.first == "\"" else { return nil }
        rest = rest.dropFirst()
        var out = ""
        var escaped = false
        for ch in rest {
            if escaped { out.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "\"" { break }
            out.append(ch)
        }
        return out
    }
}
