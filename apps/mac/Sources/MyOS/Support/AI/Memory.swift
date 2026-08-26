import Foundation

/// What Catherine remembers about you between conversations.
///
/// Deliberately NOT a transcript. A memory is a durable fact — a project, a
/// preference, a decision, a way you work — that stays true after the chat that
/// produced it is gone. Everything here is pure data and pure logic so the
/// hard part (deciding what is worth keeping) can be tested without a model.
///
/// Stored under `myos.memory`, which means it is encrypted with the rest of the
/// vault and syncs to every device like any other module.

enum MemoryCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case identity, preference, goal, project, skill, decision, relationship, workflow, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .identity:     return "Identity"
        case .preference:   return "Preference"
        case .goal:         return "Goal"
        case .project:      return "Project"
        case .skill:        return "Skill"
        case .decision:     return "Decision"
        case .relationship: return "People"
        case .workflow:     return "Workflow"
        case .other:        return "Other"
        }
    }

    var icon: String {
        switch self {
        case .identity:     return "person.fill"
        case .preference:   return "slider.horizontal.3"
        case .goal:         return "target"
        case .project:      return "hammer.fill"
        case .skill:        return "wrench.and.screwdriver.fill"
        case .decision:     return "signpost.right.fill"
        case .relationship: return "person.2.fill"
        case .workflow:     return "arrow.triangle.branch"
        case .other:        return "circle.dashed"
        }
    }
}

/// Where a memory came from. This drives trust: something you said to remember
/// is never quietly overwritten by something a model inferred.
enum MemorySource: String, Codable, Hashable {
    /// You explicitly asked for it ("remember that…").
    case stated
    /// The extraction pass pulled it out of a conversation.
    case extracted
    /// Typed or edited by hand in Settings → Memory.
    case manual
}

struct MemoryItem: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var category: MemoryCategory
    /// 1 (trivia) … 5 (core to who they are). Drives what survives the budget.
    var importance: Int
    var source: MemorySource
    /// 0…1. Always 1 for `stated`/`manual` — you said it, so it is true.
    var confidence: Double
    var createdAt: String
    var updatedAt: String
    /// Pinned memories are always in context, budget permitting.
    var pinned: Bool

    init(id: String = UUID().uuidString.lowercased(),
         content: String,
         category: MemoryCategory = .other,
         importance: Int = 3,
         source: MemorySource = .extracted,
         confidence: Double = 1,
         createdAt: String = "",
         updatedAt: String = "",
         pinned: Bool = false) {
        self.id = id
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.importance = max(1, min(5, importance))
        self.source = source
        self.confidence = source == .extracted ? max(0, min(1, confidence)) : 1
        self.createdAt = createdAt
        self.updatedAt = updatedAt.isEmpty ? createdAt : updatedAt
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case id, content, category, importance, source, confidence, createdAt, updatedAt, pinned
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString.lowercased()
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        category = (try? c.decode(MemoryCategory.self, forKey: .category)) ?? .other
        importance = max(1, min(5, (try? c.decode(Int.self, forKey: .importance)) ?? 3))
        source = (try? c.decode(MemorySource.self, forKey: .source)) ?? .extracted
        confidence = max(0, min(1, (try? c.decode(Double.self, forKey: .confidence)) ?? 1))
        createdAt = (try? c.decode(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? createdAt
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }
}

struct MemoryState: Codable, Hashable {
    var items: [MemoryItem] = []

    enum CodingKeys: String, CodingKey { case items }

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([MemoryItem].self, forKey: .items)) ?? []
    }
}

/// Pure decisions about memory: what is worth keeping, what is a duplicate of
/// something already known, and what earns a place in a bounded context.
enum MemoryBank {

    // MARK: - Keeping memory clean

    /// Why a candidate memory was thrown away. Returned rather than logged so
    /// the extraction pass can be inspected in debug mode.
    enum Rejection: String, Equatable {
        case tooShort, tooLong, ephemeral, lowConfidence, duplicate, sensitive
    }

    /// Phrases that mark something as true *now* rather than true in general.
    /// "I ate dosa today" is a diary line; the journal already holds those.
    private static let ephemeralMarkers = [
        "today", "tonight", "this morning", "this evening", "right now",
        "just now", "yesterday", "tomorrow", "this week", "at the moment",
        "currently feeling", "i ate", "i'm eating", "i had lunch", "i had dinner"
    ]

    /// Things never stored off the back of an inference. If you want a password
    /// or a card number remembered you have to say so outright, and then it is
    /// `stated` rather than `extracted`.
    private static let sensitiveMarkers = [
        "password", "passphrase", "otp", "cvv", "pin is", "card number",
        "aadhaar", "aadhar", "pan number", "api key", "secret key", "private key",
        "seed phrase", "account number"
    ]

    /// Signals that a sentence is about how things *are*, not how they are today.
    private static let durableMarkers = [
        "always", "never", "usually", "prefer", "from now on", "going forward",
        "i use", "i work", "i'm building", "i am building", "my main", "my goal",
        "i decided", "we decided", "i hate", "i love", "i'm learning",
        "i am learning", "remember that", "my name is", "i live in", "default to"
    ]

    /// Should this candidate become a long-term memory?
    ///
    /// `stated` and `manual` memories skip the durability test — you asked, so it
    /// is kept — but they still can't be empty and still can't duplicate.
    static func judge(_ candidate: MemoryItem, against existing: [MemoryItem]) -> Rejection? {
        let text = candidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = text.lowercased()

        if text.count < 8 { return .tooShort }
        if text.count > 400 { return .tooLong }

        if candidate.source == .extracted {
            if sensitiveMarkers.contains(where: { low.contains($0) }) { return .sensitive }
            if candidate.confidence < 0.6 { return .lowConfidence }
            // Ephemeral unless something in it reads as durable: "I always eat
            // dosa for breakfast" is a preference, "I ate dosa today" is not.
            let ephemeral = ephemeralMarkers.contains { low.contains($0) }
            let durable = durableMarkers.contains { low.contains($0) }
            if ephemeral && !durable { return .ephemeral }
        }

        if existing.contains(where: { isDuplicate($0.content, text) }) { return .duplicate }
        return nil
    }

    /// Is it even worth asking a model whether this turn held a fact?
    ///
    /// Extraction costs a second request, and the honest answer for most chat
    /// turns ("what's the weather", "thanks", "how do I centre a div") is no.
    /// This cheap gate keeps the pass rare, which is also what keeps the memory
    /// bank clean — the fewer candidates, the less there is to pollute it with.
    static func mightContainMemory(_ text: String) -> Bool {
        let low = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard low.count >= 12 else { return false }
        // Checked first: "do you remember what I always eat?" is asking what she
        // knows, not telling her something new.
        guard !low.hasSuffix("?") else { return false }
        if low.contains("remember") || low.contains("don't forget") { return true }
        return durableMarkers.contains { low.contains($0) }
    }

    /// Near-duplicate detection on normalised word sets. Deliberately blunt —
    /// the cost of missing a duplicate is one redundant line in context, and the
    /// cost of a false positive is losing a real memory, so it errs high.
    static func isDuplicate(_ a: String, _ b: String) -> Bool {
        let x = tokens(a), y = tokens(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        // Normalised by the LARGER set. Dividing by the smaller one gave any
        // strict superset a perfect 1.0, so the more specific fact was the one
        // thrown away: with "allergic to peanuts" already stored, "also allergic
        // to shellfish" scored as a duplicate and the shellfish allergy was
        // never written down. The comment above says the expensive mistake is a
        // false positive; this is the formula that actually means it.
        let overlap = Double(x.intersection(y).count)
        return overlap / Double(max(x.count, y.count)) >= 0.8
    }

    static func tokens(_ s: String) -> Set<String> {
        Set(TextIndex.terms(s))
    }

    // MARK: - Choosing what goes into a prompt

    /// The memories worth showing for this message.
    ///
    /// Score is relevance to what they just asked, lifted by importance, how
    /// sure we are, and pinning. Anything scoring nothing at all is dropped —
    /// injecting the whole bank is exactly the context overload to avoid.
    static func recall(_ items: [MemoryItem], for query: String, limit: Int = 8) -> [MemoryItem] {
        guard !items.isEmpty else { return [] }
        let q = TextIndex.terms(query)
        // Inclusion is a yes/no question, asked before scoring. Importance and
        // confidence decide the ORDER of what got in; on their own they must not
        // be able to drag an unrelated memory into every single prompt.
        let rideAlong: Set<MemoryCategory> = [.identity, .preference]
        let scored: [(MemoryItem, Double)] = items.compactMap { item in
            let overlap = q.isEmpty ? 0 : Double(tokens(item.content).intersection(Set(q)).count)
            // Identity and preferences shape *how* to answer, not just what, so
            // they come along unprompted. Everything else has to earn its place.
            let relevant = overlap > 0 || item.pinned || rideAlong.contains(item.category)
            guard relevant else { return nil }
            var score = overlap * 2
            if rideAlong.contains(item.category) { score += 0.75 }
            if item.pinned { score += 3 }
            score += Double(item.importance) * 0.35
            score *= max(0.4, item.confidence)
            return (item, score)
        }
        return scored
            .sorted { $0.1 == $1.1 ? $0.0.updatedAt > $1.0.updatedAt : $0.1 > $1.1 }
            .prefix(max(0, limit))
            .map(\.0)
    }

    /// How memories are written into the prompt. One per line, category tagged,
    /// so the model can tell a hard fact from something merely inferred.
    static func promptLines(_ items: [MemoryItem]) -> [String] {
        items.map { m in
            let hedge = m.source == .extracted && m.confidence < 0.85 ? " (unconfirmed)" : ""
            return "- [\(m.category.rawValue)] \(m.content)\(hedge)"
        }
    }
}
