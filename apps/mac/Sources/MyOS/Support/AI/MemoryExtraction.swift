import Foundation

/// Learning from a conversation without turning into a transcript.
///
/// Two gates stand between "he said something" and "she remembers it forever":
///
/// 1. `MemoryBank.mightContainMemory` — a cheap local check that skips the
///    request entirely for the ordinary chat turn, which is most of them.
/// 2. `MemoryBank.judge` — the deterministic filter every candidate must pass,
///    which is where ephemera, near-duplicates and anything sensitive die.
///
/// The model's opinion sits between the two and is never the last word. That
/// ordering is what keeps the bank small enough to be useful.
extension AppState {

    /// The primary path is the `remember` tool, which fires when he says
    /// "remember this". This is the safety net for facts dropped in passing.
    func learnFromExchange(user: String, assistant: String) async {
        guard MemoryBank.mightContainMemory(user) else { return }
        guard !assistant.isEmpty else { return }

        let known = sortedMemory.prefix(40).map(\.content)
        let candidates: [APIClient.MemoryCandidateDTO]
        do {
            candidates = try await api.extractMemories(user: user, assistant: assistant, known: known)
        } catch {
            return   // learning is a bonus; never surface a failure here
        }

        var stored: [MemoryItem] = []
        for c in candidates {
            let item = MemoryItem(content: c.content,
                                  category: MemoryCategory(rawValue: c.category) ?? .other,
                                  importance: c.importance,
                                  source: .extracted,
                                  confidence: c.confidence,
                                  createdAt: Self.nowStamp())
            // Judge against what is already there PLUS what this same pass has
            // just added, or two rephrasings of one fact both get through.
            if MemoryBank.judge(item, against: memory.items + stored) == nil {
                stored.append(item)
            }
        }
        for item in stored { addMemory(item) }
    }
}
