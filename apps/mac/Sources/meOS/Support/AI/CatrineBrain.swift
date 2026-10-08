import Foundation

/// One assembled prompt context, plus what went into it — the extra detail is
/// what the debug sheet shows, so an answer can always be traced back to the
/// notes and memories it was built from.
struct CatrineContext {
    var assembly: ContextBuilder.Result
    var memories: [MemoryItem]
    var documents: [RetrievalHit]

    var text: String { assembly.text }
}

/// Catherine's long-term memory, and the context she reasons from.
///
/// Memory lives under `myos.memory`, so it is encrypted, synced and wiped with
/// everything else — no separate store to secure. Context is assembled here per
/// message rather than dumped wholesale: what she gets is what this question
/// actually needs.
extension AppState {

    // MARK: - Memory

    var sortedMemory: [MemoryItem] {
        memory.items.sorted {
            $0.pinned != $1.pinned ? $0.pinned
                : ($0.importance == $1.importance ? $0.updatedAt > $1.updatedAt
                                                  : $0.importance > $1.importance)
        }
    }

    @discardableResult
    func addMemory(_ item: MemoryItem) -> MemoryItem {
        var m = item
        if m.createdAt.isEmpty { m.createdAt = Self.nowStamp() }
        m.updatedAt = Self.nowStamp()
        memory.items.insert(m, at: 0)
        push(StateKey.memory, memory)
        return m
    }

    func updateMemory(_ item: MemoryItem) {
        guard let i = memory.items.firstIndex(where: { $0.id == item.id }) else { return }
        var m = item
        m.updatedAt = Self.nowStamp()
        memory.items[i] = m
        push(StateKey.memory, memory)
    }

    func deleteMemory(_ id: String) {
        memory.items.removeAll { $0.id == id }
        push(StateKey.memory, memory)
    }

    /// Delete everything matching a description, returning what went — the model
    /// reports this back so "forget that" never silently does nothing.
    @discardableResult
    func forgetMemories(matching query: String) -> [String] {
        let doomed = MemoryBank.recall(memory.items, for: query, limit: 5)
            .filter { MemoryBank.isDuplicate($0.content, query) || relevantEnoughToForget($0, query) }
        guard !doomed.isEmpty else { return [] }
        let ids = Set(doomed.map(\.id))
        memory.items.removeAll { ids.contains($0.id) }
        push(StateKey.memory, memory)
        return doomed.map(\.content)
    }

    /// Forgetting is destructive, so it needs a real term overlap — not just
    /// "this ranked top of a weak search".
    private func relevantEnoughToForget(_ item: MemoryItem, _ query: String) -> Bool {
        let q = Set(TextIndex.terms(query))
        guard !q.isEmpty else { return false }
        // Most of the query's terms, not merely one. A single shared word meant
        // "forget what you know about the meOS beta launch" also deleted "main
        // project is meOS, a personal second brain" — both contain `meos`, both
        // were in the top five, and both went. Memory has no undo.
        // All but one of the query's terms. A flat 0.6 ratio meant any two-term
        // query needed a perfect match — "peanut allergy" against the stored
        // "allergic to peanuts" stems to one shared term out of two, scores 0.5,
        // and forgetting silently did nothing on the most ordinary phrasing
        // there is.
        let shared = MemoryBank.tokens(item.content).intersection(q).count
        return shared >= max(1, q.count - 1)
    }

    // MARK: - Context

    /// Everything Catherine should know for THIS message, in priority order and
    /// under a character ceiling.
    ///
    /// Ordering note: tool results sit near the top even though they arrive last.
    /// The model asked for them, so they are the most relevant thing in the
    /// prompt — trimming them first would be exactly backwards.
    func catrineContext(for query: String,
                        toolResults: [String] = [],
                        // 8000, matching the server's own slice. At 9000 the
                        // last thousand characters were cut mid-line by the
                        // Worker, which defeats ContextBuilder's whole contract
                        // of dropping a section whole rather than clipping it —
                        // a retrieved note arrived truncated with no marker.
                        budget: Int = 8000) -> CatrineContext {
        var sections: [ContextSection] = []

        sections.append(ContextSection(
            heading: "NOW",
            lines: [
                "Today is \(Fmt.longDay(todayKey)) (\(todayKey)).",
                "Any date you write must be YYYY-MM-DD and on or after \(todayKey) unless they are talking about the past."
            ],
            priority: 0))

        var who: [String] = []
        let p = profile
        var line = p.name.isEmpty ? "Name not set." : "Name: \(p.name)."
        if let a = p.age { line += " Age \(a)." }
        if !p.city.isEmpty { line += " Lives in \(p.city)." }
        if !p.role.isEmpty { line += " Role: \(p.role)." }
        if !p.work.isEmpty { line += " Work: \(p.work)." }
        who.append(line)
        let about = p.about.trimmingCharacters(in: .whitespacesAndNewlines)
        if !about.isEmpty { who.append("In their words: \(about)") }
        sections.append(ContextSection(heading: "WHO THEY ARE", lines: who, priority: 1))

        if !toolResults.isEmpty {
            sections.append(ContextSection(
                heading: "TOOL RESULTS (you looked these up — quote them, don't embellish)",
                lines: toolResults, priority: 2))
        }

        let recalled = MemoryBank.recall(memory.items, for: query)
        if !recalled.isEmpty {
            sections.append(ContextSection(
                heading: "WHAT YOU REMEMBER ABOUT THEM",
                lines: MemoryBank.promptLines(recalled), priority: 3))
        }

        // Only worth searching when there is something to search for. A bare
        // "hey" should not drag six notes into the prompt.
        let hits = TextIndex.terms(query).isEmpty ? [] : searchBrain(query, limit: 5)
        if !hits.isEmpty {
            sections.append(ContextSection(
                heading: "FROM THEIR meOS (retrieved — if it isn't here, you don't know it)",
                lines: Retriever.promptLines(hits), priority: 4))
        }

        sections.append(ContextSection(heading: "TODAY", lines: todayLines(), priority: 5))

        let assembled = ContextBuilder.assemble(sections, budget: budget)
        return CatrineContext(assembly: assembled, memories: recalled, documents: hits)
    }

    /// The compact daily state. Deliberately short — it used to be most of the
    /// prompt, and reciting calorie numbers at someone asking about their code
    /// is how an assistant starts feeling like a form letter.
    private func todayLines() -> [String] {
        var l: [String] = []
        var fit = "Fitness goal \(fitnessProfile.goal.label)"
        if let w = latestWeightKg { fit += ", weight \(Fmt.trimKg(w))kg" }
        if let tw = fitnessProfile.targetWeightKg { fit += ", target \(Fmt.trimKg(tw))kg" }
        l.append(fit + ".")
        let eaten = consumed(todayKey)
        if let cal = calorieTargets() {
            l.append("Ate \(Int(eaten.calories)) of \(cal.goalCalories) kcal, \(Int(eaten.protein)) of \(cal.proteinG)g protein.")
        }
        let todos = todayPlan().todos
        if !todos.isEmpty {
            l.append("Focus list: \(todos.filter(\.done).count)/\(todos.count) done — " +
                     todos.prefix(5).map(\.text).joined(separator: "; ") + ".")
        }
        let e = journalEntry(todayKey)
        if let mood = e.mood { l.append("Mood today \(mood)/5.") }
        // The streak is steps now — a journal streak measured whether the day
        // was written down, not whether it was worked.
        l.append("Steps today \(steps(on: todayKey).formatted()) of \(stepGoals.daily.formatted()); \(stepStreak)-day streak.")
        return l
    }
}

extension Fmt {
    /// "Wednesday 19 August 2026" — the human form used in the prompt.
    static func longDay(_ key: String) -> String {
        guard let d = CalMath.date(fromKey: String(key.prefix(10))) else { return key }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE d MMMM yyyy"
        return f.string(from: d)
    }
}
