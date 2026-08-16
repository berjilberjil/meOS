import Foundation

/// A command Catherine can emit at the end of a reply so MyOS actually does it.
struct MentorAction: Equatable {
    enum Kind: String, Equatable {
        case createEvent = "create_event"
        case createShoot = "create_shoot"
        case createNote = "create_note"
        case lockNote = "lock_note"
        case addFocus = "add_focus"
        case logFood = "log_food"
    }

    let kind: Kind
    let fields: [String: String]
}

struct MentorActionParse {
    let visible: String
    let actions: [MentorAction]
}

enum ChatAction {
    /// Pulls `ACTION kind key="value"` lines off the bottom of a reply.
    static func parse(_ raw: String) -> MentorActionParse {
        var visible: [String] = []
        var actions: [MentorAction] = []
        for line in raw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.uppercased().hasPrefix("ACTION ") {
                if let a = parseLine(String(t.dropFirst(7))) { actions.append(a) }
            } else {
                visible.append(line)
            }
        }
        let spoken = visible.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MentorActionParse(visible: spoken, actions: actions)
    }

    private static func parseLine(_ rest: String) -> MentorAction? {
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first,
              let kind = MentorAction.Kind(rawValue: first.lowercased()) else { return nil }
        var fields: [String: String] = [:]
        let tail = parts.count > 1 ? String(parts[1]) : ""
        let regex = try? NSRegularExpression(pattern: #"(\w+)="([^"]*)""#)
        let ns = tail as NSString
        regex?.matches(in: tail, range: NSRange(location: 0, length: ns.length)).forEach { m in
            guard m.numberOfRanges == 3 else { return }
            fields[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
        }
        return MentorAction(kind: kind, fields: fields)
    }
}
