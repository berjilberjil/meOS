import Foundation

/// The things Catherine can actually do.
///
/// These are real tool calls, not the old `ACTION` lines scraped off the end of
/// a reply. The model asks for a tool, the app runs it here and hands back the
/// result, and only then does the model answer. That is the difference between
/// "I think you decided X" and "your note from March says X".
///
/// Execution is deliberately on-device. Every tool reads or writes the vault
/// that is already unlocked in this process, so a tool can only ever touch the
/// data of the person holding the passphrase — there is no server-side path to
/// anyone's notes, and no way for one account's data to reach another's context.
///
/// The declarations travel with each request rather than being duplicated on the
/// server, so the two can never drift out of sync.

struct CatrineTool {
    let name: String
    let description: String
    /// JSON Schema for the arguments, sent verbatim to the model.
    let parameters: [String: Any]
    /// Writes are called out so the loop can bound and report them separately.
    let mutates: Bool

    init(_ name: String, _ description: String, _ properties: [String: Any],
         required: [String] = [], mutates: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = ["type": "object", "properties": properties, "required": required]
        self.mutates = mutates
    }
}

enum CatrineToolbox {
    private static let query: [String: Any] = ["type": "string", "description": "What to look for."]
    private static let limit: [String: Any] = ["type": "integer", "description": "Max results (default 6)."]

    static let all: [CatrineTool] = [
        // MARK: Reads
        CatrineTool("search_brain",
                    "Search everything in MyOS at once — notes, journal, events, focus lists, purchases, videos. Use this when you don't know which module holds the answer.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_notes",
                    "Search the user's notes. Use for anything they wrote down: ideas, decisions, specs, drafts. Locked notes are never returned.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_journal",
                    "Search journal entries — how a day went, wins, mistakes, lessons, gratitude, mood.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_events",
                    "Search logged life events (trips, milestones) by title or note.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_purchases",
                    "Search things the user owns, with price, purchase date and payback progress.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("search_memory",
                    "Search what you already remember about the user. Use before claiming you don't know something about them.",
                    ["query": query, "limit": limit], required: ["query"]),
        CatrineTool("get_todos",
                    "The focus list for a day. Omit the date for today.",
                    ["date": ["type": "string", "description": "yyyy-MM-dd. Defaults to today."]]),
        CatrineTool("get_upcoming",
                    "Events coming up, soonest first.",
                    ["limit": limit]),

        // MARK: Writes
        CatrineTool("remember",
                    "Store a durable fact about the user — a project, preference, goal, decision or way they work. Only for things that stay true after this conversation. Never store passwords or keys unless they explicitly asked you to.",
                    ["content": ["type": "string", "description": "The fact, in one sentence, written about the user."],
                     "category": ["type": "string",
                                  "enum": MemoryCategory.allCases.map(\.rawValue),
                                  "description": "Which kind of fact this is."],
                     "importance": ["type": "integer", "description": "1 trivia … 5 core to who they are. Default 3."]],
                    required: ["content"], mutates: true),
        CatrineTool("forget",
                    "Delete remembered facts that match a description. Use when the user says to forget something or corrects you.",
                    ["query": query], required: ["query"], mutates: true),
        CatrineTool("create_note",
                    "Create a note in MyOS.",
                    ["title": ["type": "string"], "body": ["type": "string"]],
                    required: ["title"], mutates: true),
        CatrineTool("add_focus",
                    "Add a to-do to today's focus list.",
                    ["text": ["type": "string"]], required: ["text"], mutates: true),
        CatrineTool("create_event",
                    "Log a life event on a date.",
                    ["title": ["type": "string"],
                     "date": ["type": "string", "description": "yyyy-MM-dd, today or later."]],
                    required: ["title", "date"], mutates: true)
    ]

    static func byName(_ n: String) -> CatrineTool? { all.first { $0.name == n } }

    /// The shape the chat endpoint expects.
    static func wireFormat() -> [[String: Any]] {
        all.map { ["name": $0.name, "description": $0.description, "parameters": $0.parameters] }
    }
}

// MARK: - Execution

extension AppState {

    /// Run one tool and return a JSON-encodable result.
    ///
    /// Never throws: a failure is reported back to the model as data, so it can
    /// say "I couldn't find that" instead of the whole turn collapsing.
    func runCatrineTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
        func str(_ k: String) -> String {
            (args[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func int(_ k: String) -> Int? {
            if let i = args[k] as? Int { return i }
            if let d = args[k] as? Double { return Int(d) }
            if let s = args[k] as? String { return Int(s) }
            return nil
        }
        let cap = max(1, min(int("limit") ?? 6, 12))

        func found(_ hits: [RetrievalHit]) -> [String: Any] {
            guard !hits.isEmpty else {
                return ["found": 0,
                        "note": "Nothing in MyOS matches that. Say so — do not invent an answer."]
            }
            return ["found": hits.count,
                    "results": hits.map { h in
                        ["kind": h.doc.kind.rawValue, "title": h.doc.title,
                         "date": h.doc.date, "text": h.doc.snippet()]
                    }]
        }

        switch name {
        case "search_brain":     return found(searchBrain(str("query"), limit: cap))
        case "search_notes":     return found(searchBrain(str("query"), kinds: [.note], limit: cap))
        case "search_journal":   return found(searchBrain(str("query"), kinds: [.journal], limit: cap))
        case "search_events":    return found(searchBrain(str("query"), kinds: [.event], limit: cap))
        case "search_purchases": return found(searchBrain(str("query"), kinds: [.stuff], limit: cap))

        case "search_memory":
            let hits = MemoryBank.recall(memory.items, for: str("query"), limit: cap)
            guard !hits.isEmpty else {
                return ["found": 0, "note": "You don't remember anything about that yet."]
            }
            return ["found": hits.count,
                    "memories": hits.map { ["content": $0.content, "category": $0.category.rawValue,
                                            "since": $0.createdAt] }]

        case "get_todos":
            let day = str("date").isEmpty ? todayKey : String(str("date").prefix(10))
            let todos = plan(for: day).todos
            return ["date": day, "count": todos.count,
                    "todos": todos.map { ["text": $0.text, "done": $0.done,
                                          "minutes_focused": $0.spent / 60] }]

        case "get_upcoming":
            let upcoming = events.filter { $0.date >= todayKey }
                .sorted { $0.date < $1.date }.prefix(cap)
            return ["today": todayKey,
                    "events": upcoming.map { ["title": $0.title, "date": $0.date, "note": $0.note] }]

        // MARK: Writes

        case "remember":
            let content = str("content")
            guard !content.isEmpty else { return ["ok": false, "error": "nothing to remember"] }
            let category = MemoryCategory(rawValue: str("category")) ?? .other
            let candidate = MemoryItem(content: content, category: category,
                                       importance: int("importance") ?? 3,
                                       source: .stated, createdAt: Self.nowStamp())
            if let why = MemoryBank.judge(candidate, against: memory.items) {
                return ["ok": false, "skipped": why.rawValue,
                        "note": why == .duplicate ? "You already remember this." : "Not stored."]
            }
            addMemory(candidate)
            return ["ok": true, "remembered": content]

        case "forget":
            let gone = forgetMemories(matching: str("query"))
            return gone.isEmpty
                ? ["ok": false, "note": "Nothing remembered matches that."]
                : ["ok": true, "forgot": gone]

        case "create_note":
            guard !str("title").isEmpty else { return ["ok": false, "error": "title required"] }
            applyMentorActions([MentorAction(kind: .createNote,
                                             fields: ["title": str("title"), "body": str("body")])])
            return ["ok": true, "created": str("title")]

        case "add_focus":
            guard !str("text").isEmpty else { return ["ok": false, "error": "text required"] }
            applyMentorActions([MentorAction(kind: .addFocus, fields: ["text": str("text")])])
            return ["ok": true, "added": str("text")]

        case "create_event":
            guard !str("title").isEmpty, !str("date").isEmpty else {
                return ["ok": false, "error": "title and date required"]
            }
            applyMentorActions([MentorAction(kind: .createEvent,
                                             fields: ["title": str("title"), "date": str("date")])])
            return ["ok": true, "created": str("title"), "date": str("date")]

        default:
            return ["ok": false, "error": "no such tool: \(name)"]
        }
    }
}
