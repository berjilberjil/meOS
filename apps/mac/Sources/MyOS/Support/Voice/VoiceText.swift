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
        let flat = text
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
