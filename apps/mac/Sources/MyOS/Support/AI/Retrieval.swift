import Foundation

/// Searching your second brain, on the device that can read it.
///
/// MyOS state is end-to-end encrypted: the server holds ciphertext and could not
/// chunk or embed a note if it wanted to. So retrieval runs here, over state
/// that is already decrypted in memory, and only the handful of passages that
/// actually matter are sent with the question. Nothing new is stored in the
/// clear anywhere.
///
/// The ranking is BM25 with field weighting and a recency lift — no embeddings.
/// For one person's notes that is a genuinely strong baseline, and everything
/// sits behind `Retriever` so a semantic scorer can replace it later without
/// touching a single caller.

// MARK: - Text

enum TextIndex {
    /// Words that carry no signal in a personal search. "my" and "I" are in here
    /// on purpose — nearly every question he asks contains them.
    private static let stop: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "did", "do", "does",
        "for", "from", "had", "has", "have", "he", "her", "his", "how", "i", "if",
        "in", "is", "it", "its", "me", "my", "of", "on", "or", "she", "should",
        "so", "that", "the", "their", "them", "then", "there", "these", "they",
        "this", "to", "was", "we", "were", "what", "when", "where", "which", "who",
        "why", "will", "with", "you", "your", "about", "can", "could", "would",
        "am", "been", "being", "into", "over", "our", "us", "just", "get", "got",
        // Quantifiers: "every project" and "all my projects" say the same thing,
        // and treating them as signal is what stopped duplicate memories being
        // recognised as duplicates.
        "all", "every", "each", "any", "some", "many", "most", "both"
    ]

    /// Lowercase word stems, stop words dropped.
    ///
    /// The stemming is intentionally crude — trailing plural and tense endings
    /// only — because aggressive stemming mangles the product names, project
    /// names and jargon that make up most of what is worth finding here.
    static func terms(_ raw: String) -> [String] {
        raw.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
            .filter { $0.count > 1 && !stop.contains($0) }
            .map(stem)
    }

    static func stem(_ w: String) -> String {
        for suffix in ["ing", "ies", "ed", "es"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            if suffix == "ies" { return String(w.dropLast(3)) + "y" }
            return String(w.dropLast(suffix.count))
        }
        // A bare trailing "s" is the dangerous one: it turns MyOS into "myo" and
        // stops the app finding its own name. Words that end in a doubled or
        // vowel-led "s" are almost never plurals, so they keep it.
        if w.count >= 4, w.hasSuffix("s"),
           !["ss", "us", "os", "is", "as"].contains(String(w.suffix(2))) {
            return String(w.dropLast())
        }
        return w
    }
}

// MARK: - What can be searched

enum DocKind: String, Codable, CaseIterable, Hashable {
    case note, journal, event, todo, stuff, video, memory

    /// How it is introduced in the prompt, so the model can cite it honestly.
    var label: String {
        switch self {
        case .note:    return "Note"
        case .journal: return "Journal"
        case .event:   return "Event"
        case .todo:    return "To-do"
        case .stuff:   return "Purchase"
        case .video:   return "Video"
        case .memory:  return "Memory"
        }
    }
}

/// One searchable thing, flattened out of whatever module it came from.
struct RetrievalDoc: Identifiable, Hashable {
    var id: String
    var kind: DocKind
    var title: String
    var body: String
    /// `yyyy-MM-dd`, for the recency lift. Empty means undated.
    var date: String
    var pinned: Bool = false

    /// A short, quotable form for the prompt. Long notes are cut rather than
    /// summarised — an honest truncation beats a lossy paraphrase.
    func snippet(limit: Int = 420) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        // Prefer breaking on a sentence, then a word, before a hard slice.
        if let dot = cut.lastIndex(of: "."), cut.distance(from: cut.startIndex, to: dot) > limit / 2 {
            return String(cut[...dot]) + " …"
        }
        if let space = cut.lastIndex(of: " ") { return String(cut[..<space]) + " …" }
        return String(cut) + " …"
    }
}

struct RetrievalHit: Identifiable, Hashable {
    var doc: RetrievalDoc
    var score: Double
    var id: String { doc.id }
}

// MARK: - Ranking

enum Retriever {
    /// Standard BM25 constants. `b` is left at 0.75: note length varies wildly
    /// here (a one-line thought next to a design doc) and length normalisation
    /// is what stops the long ones swamping everything.
    private static let k1 = 1.2
    private static let b = 0.75
    /// A title hit is worth three body hits — titles are how notes are named.
    private static let titleWeight = 3.0

    /// The passages worth putting in front of the model for this question.
    ///
    /// - Parameter floor: minimum score to be included at all. Returning nothing
    ///   is a valid, useful answer — it is what lets Catherine say "I don't have
    ///   that" instead of inventing it.
    static func search(_ query: String,
                       in docs: [RetrievalDoc],
                       limit: Int = 6,
                       floor: Double = 0.35,
                       today: String = "") -> [RetrievalHit] {
        let q = Array(Set(TextIndex.terms(query)))
        guard !q.isEmpty, !docs.isEmpty else { return [] }

        let fields = docs.map { (title: TextIndex.terms($0.title), body: TextIndex.terms($0.body)) }
        let lengths = fields.map { Double($0.title.count) * titleWeight + Double($0.body.count) }
        let avgLen = max(1, lengths.reduce(0, +) / Double(lengths.count))

        // Document frequency per query term, over this corpus.
        var df: [String: Int] = [:]
        for f in fields {
            let present = Set(f.title + f.body)
            for t in q where present.contains(t) { df[t, default: 0] += 1 }
        }
        let n = Double(docs.count)

        var hits: [RetrievalHit] = []
        for (i, doc) in docs.enumerated() {
            var score = 0.0
            for t in q {
                let count = df[t] ?? 0
                guard count > 0 else { continue }
                let tf = Double(fields[i].title.filter { $0 == t }.count) * titleWeight
                    + Double(fields[i].body.filter { $0 == t }.count)
                guard tf > 0 else { continue }
                // Floored: textbook IDF drives a term present in every document to
                // zero, which is right for web search and wrong for one person's
                // notes — searching "postgres" when everything mentions postgres
                // should still return the best postgres notes, not nothing.
                let idf = max(0.3, log(1 + (n - Double(count) + 0.5) / (Double(count) + 0.5)))
                let norm = tf * (k1 + 1) / (tf + k1 * (1 - b + b * lengths[i] / avgLen))
                score += idf * norm
            }
            guard score > 0 else { continue }
            score *= recencyLift(doc.date, today: today)
            if doc.pinned { score *= 1.25 }
            hits.append(RetrievalHit(doc: doc, score: score))
        }

        return hits
            .filter { $0.score >= floor }
            .sorted { $0.score == $1.score ? $0.doc.date > $1.doc.date : $0.score > $1.score }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Recent things matter more, but old things never disappear — a decision
    /// made two years ago is still the decision. Ranges 1.0 … 1.5.
    static func recencyLift(_ date: String, today: String) -> Double {
        guard !date.isEmpty, !today.isEmpty,
              let then = CalMath.date(fromKey: String(date.prefix(10))),
              let now = CalMath.date(fromKey: String(today.prefix(10))) else { return 1 }
        let days = max(0, now.timeIntervalSince(then) / 86_400)
        return 1 + 0.5 * exp(-days / 180)
    }

    /// How retrieved passages are written into the prompt.
    static func promptLines(_ hits: [RetrievalHit]) -> [String] {
        hits.map { hit in
            let title = hit.doc.title.isEmpty ? "(untitled)" : hit.doc.title
            let when = hit.doc.date.isEmpty ? "" : " · \(hit.doc.date)"
            return "- \(hit.doc.kind.label): \"\(title)\"\(when)\n  \(hit.doc.snippet())"
        }
    }
}
