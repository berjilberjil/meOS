import Foundation

/// Flattens the modules into one searchable pile.
///
/// This is the whole second brain as far as Catherine is concerned: notes,
/// journal, events, focus lists, purchases and the video log. Built on demand
/// from state that is already decrypted and in memory — nothing is cached to
/// disk, so there is no second copy of your life to keep in sync or secure.
extension AppState {

    /// Locked notes stay out entirely. The lock exists to keep a note off the
    /// screen; quietly feeding it to a model would be a strange way to honour it.
    func retrievalCorpus(kinds: Set<DocKind> = Set(DocKind.allCases)) -> [RetrievalDoc] {
        var docs: [RetrievalDoc] = []

        if kinds.contains(.note) {
            for n in notes where !n.locked {
                docs.append(RetrievalDoc(id: "note:\(n.id)", kind: .note, title: n.title,
                                         body: n.body, date: String(n.updatedAt.prefix(10)),
                                         pinned: n.pinned))
            }
        }

        if kinds.contains(.journal) {
            for (day, e) in journal {
                var parts: [String] = [e.morning, e.night]
                if !e.wins.isEmpty { parts.append("Wins: " + e.wins.joined(separator: "; ")) }
                if !e.mistakes.isEmpty { parts.append("Mistakes: " + e.mistakes.joined(separator: "; ")) }
                if !e.lessons.isEmpty { parts.append("Lessons: " + e.lessons.joined(separator: "; ")) }
                if !e.gratitude.isEmpty { parts.append("Grateful for: " + e.gratitude.joined(separator: "; ")) }
                guard !parts.isEmpty else { continue }
                docs.append(RetrievalDoc(id: "journal:\(day)", kind: .journal,
                                         title: "Journal \(day)", body: parts.joined(separator: "\n"),
                                         date: day))
            }
        }

        if kinds.contains(.event) {
            for e in events {
                docs.append(RetrievalDoc(id: "event:\(e.id)", kind: .event, title: e.title,
                                         body: e.note, date: e.date, pinned: e.special))
            }
        }

        if kinds.contains(.todo) {
            // One doc per day rather than per to-do: a single line ("ship the cut")
            // is too thin to rank, but a day's list has enough shape to match on.
            for (day, plan) in days where !plan.todos.isEmpty {
                let lines = plan.todos.map { "\($0.done ? "[x]" : "[ ]") \($0.text)" }
                docs.append(RetrievalDoc(id: "todo:\(day)", kind: .todo,
                                         title: "Focus list \(day)", body: lines.joined(separator: "\n"),
                                         date: day))
            }
        }

        if kinds.contains(.stuff) {
            for item in belongings.items {
                let cat = belongingCategory(for: item).name
                let body = [
                    "\(cat) · ₹\(item.pricePaise / 100) · bought \(item.boughtOn)",
                    item.note, item.link
                ].filter { !$0.isEmpty }.joined(separator: "\n")
                docs.append(RetrievalDoc(id: "stuff:\(item.id)", kind: .stuff, title: item.name,
                                         body: body, date: item.boughtOn))
            }
        }

        if kinds.contains(.video) {
            for v in watch {
                let body = [v.channel, v.category.label, v.takeaway, v.url]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
                docs.append(RetrievalDoc(id: "video:\(v.id)", kind: .video,
                                         title: v.title.isEmpty ? v.url : v.title,
                                         body: body, date: String(v.addedAt.prefix(10))))
            }
        }

        return docs
    }

    /// Search the second brain. Thin wrapper so callers never build a corpus by
    /// hand and accidentally leave locked notes in.
    func searchBrain(_ query: String,
                     kinds: Set<DocKind> = Set(DocKind.allCases),
                     limit: Int = 6) -> [RetrievalHit] {
        Retriever.search(query, in: retrievalCorpus(kinds: kinds), limit: limit, today: todayKey)
    }
}
