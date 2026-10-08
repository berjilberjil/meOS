import Foundation

/// Assembling the prompt context, under a budget.
///
/// The old context was a fixed block that shipped the same calorie numbers with
/// every message whether or not they were relevant. This replaces it with
/// ranked sections and a hard character ceiling: when there isn't room for
/// everything, the least useful section is dropped whole rather than every
/// section being silently clipped into nonsense.
///
/// Quality of context beats quantity — a smaller prompt with the right three
/// notes in it outperforms a huge one with all of them.

struct ContextSection: Equatable {
    var heading: String
    var lines: [String]
    /// Lower survives longer. See `AppState.catrineContext` for the running order.
    var priority: Int
    /// If there isn't room for at least this many lines, the section is dropped
    /// entirely — half a list of memories is worse than none, because the model
    /// reads what's left as the complete picture.
    var minLines: Int = 1

    var isEmpty: Bool { lines.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

enum ContextBuilder {

    /// What actually went into the prompt, for the debug view.
    struct Result: Equatable {
        var text: String
        var includedHeadings: [String]
        var droppedHeadings: [String]
        var characters: Int
    }

    static func assemble(_ sections: [ContextSection], budget: Int) -> Result {
        var used = 0
        var out: [String] = []
        var included: [String] = []
        var dropped: [String] = []

        for section in sections.filter({ !$0.isEmpty }).sorted(by: { $0.priority < $1.priority }) {
            let headingCost = section.heading.count + 2
            var kept: [String] = []
            var cost = headingCost
            for line in section.lines {
                let lineCost = line.count + 1
                if used + cost + lineCost > budget { break }
                kept.append(line)
                cost += lineCost
            }
            guard kept.count >= section.minLines else {
                dropped.append(section.heading)
                continue
            }
            if kept.count < section.lines.count {
                // Say so, rather than letting a clipped list read as complete.
                let hidden = section.lines.count - kept.count
                let note = "  (+\(hidden) more not shown)"
                if used + cost + note.count + 1 <= budget {
                    kept.append(note)
                    cost += note.count + 1
                }
            }
            out.append(([section.heading] + kept).joined(separator: "\n"))
            included.append(section.heading)
            used += cost
        }

        let text = out.joined(separator: "\n\n")
        return Result(text: text, includedHeadings: included,
                      droppedHeadings: dropped, characters: text.count)
    }
}

/// What one answer was built from — retrieved passages, recalled memories, tool
/// calls, timing. Kept in memory only and shown in the debug sheet; nothing here
/// is logged or sent anywhere.
struct CatrineTrace: Equatable {
    var query: String = ""
    var memories: [String] = []
    var documents: [String] = []
    var toolCalls: [String] = []
    var steps: Int = 0
    var contextCharacters: Int = 0
    var includedSections: [String] = []
    var droppedSections: [String] = []
    var latencyMs: Int = 0
    var model: String = ""
    var error: String = ""

    var isEmpty: Bool { query.isEmpty && toolCalls.isEmpty && documents.isEmpty }
}
