import Foundation

/// Turning one of Catrine's replies into speakable pieces.
///
/// Aura synthesises a whole string before it returns anything, so handing it a
/// four-sentence answer means four seconds of silence. Speaking sentence by
/// sentence means she starts almost immediately and the rest streams in behind
/// her — the difference between a conversation and a voicemail.
enum VoiceText {

    /// Abbreviations whose full stop does NOT end a sentence.
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "prof", "sr", "jr", "st",
        "vs", "etc", "e.g", "i.e", "approx", "no", "kg", "cm"
    ]

    /// Split into pieces small enough for `/api/voice/speak` to accept.
    ///
    /// Nothing is ever dropped: joining the result with a single space
    /// reproduces the input's words in order.
    static func sentences(_ text: String, maxLength: Int = 400) -> [String] {
        let flat = plain(text)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let collapsed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return [] }

        var out: [String] = []
        var current = ""

        for word in collapsed.split(separator: " ") {
            current += current.isEmpty ? String(word) : " " + word
            if endsSentence(String(word)) {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }

        return out.flatMap { split($0, maxLength: maxLength) }
    }

    /// Strip markdown so it is not read out as words.
    ///
    /// Aura says exactly what it is given: `**Deliverables:**` comes out as
    /// "star star Deliverables star star". The model is told not to use
    /// markdown (see the voice directive in VoiceCallView), but a prompt is a
    /// request and this is a guarantee.
    ///
    /// List markers are only stripped at the START of a line, so "82.5 kg"
    /// survives intact.
    static func plain(_ text: String) -> String {
        var out: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)

            // Leading markers: "## ", "1. ", "- ", "* ", "• "
            line = line.replacingOccurrences(
                of: "^(#{1,6}\\s+|[-*•]\\s+|\\d{1,2}[.)]\\s+)", with: "",
                options: [.regularExpression])

            // [text](url) -> text
            line = line.replacingOccurrences(
                of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1",
                options: [.regularExpression])

            // Emphasis and inline code. Order matters: ** before *.
            for marker in ["**", "__", "*", "_", "`"] {
                line = line.replacingOccurrences(of: marker, with: "")
            }

            if !line.isEmpty { out.append(line) }
        }
        return out.joined(separator: " ")
    }

    /// Does this word terminate a sentence?
    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last, ".?!".contains(last) else { return false }

        let body = word.trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        if body.isEmpty { return false }

        // "Dr." — a known abbreviation keeps the sentence open.
        let bare = body.lowercased().filter { $0.isLetter || $0 == "." }
        if abbreviations.contains(bare) { return false }

        // A bare number before a full stop — "82." in a list, not an ending.
        if last == ".", body.allSatisfy({ $0.isNumber || $0 == "." }) { return false }

        return true
    }

    /// Break a piece that is still too long, on word boundaries.
    private static func split(_ piece: String, maxLength: Int) -> [String] {
        guard piece.count > maxLength else { return [piece] }
        var out: [String] = []
        var current = ""
        for word in piece.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > maxLength, !current.isEmpty {
                out.append(current)
                current = String(word)
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
