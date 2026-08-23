import Foundation

/// Task Mode — the whole app collapses to one task and its timer. The switch is
/// synced, so flipping it on the Mac takes the iPhone with it on the next poll.
/// The *mode* travels; the countdown does not. Each device runs its own block and
/// banks the seconds into the shared day plan.
struct TaskModeState: Codable, Hashable {
    var on: Bool = false
    /// When it was switched on, `yyyy-MM-dd'T'HH:mm:ss`. Empty while off.
    var since: String = ""
    /// Which device flipped it, so the other one can say where it came from.
    var device: String = ""

    init(on: Bool = false, since: String = "", device: String = "") {
        self.on = on; self.since = since; self.device = device
    }

    enum CodingKeys: String, CodingKey { case on, since, device }

    /// Hand-rolled so a payload written before Task Mode existed still decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        since = try c.decodeIfPresent(String.self, forKey: .since) ?? ""
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? ""
    }
}

/// The decisions Task Mode and the menu bar share, as pure functions — no
/// SwiftUI and no AppState, so the rules are testable without a view.
enum TaskMode {
    /// The block to run next: whatever is already running if it is still
    /// unfinished, otherwise the first thing left on the list.
    static func nextTask(in todos: [FocusItem], current: String? = nil) -> FocusItem? {
        if let current, let item = todos.first(where: { $0.id == current }), !item.done { return item }
        return todos.first { !$0.done }
    }

    /// Everything still to do, minus the one in the ring.
    static func remaining(_ todos: [FocusItem], excluding id: String? = nil) -> [FocusItem] {
        todos.filter { !$0.done && $0.id != id }
    }

    static func doneCount(_ todos: [FocusItem]) -> Int { todos.filter(\.done).count }

    /// True once there is a list and every item on it is done.
    static func dayCrushed(_ todos: [FocusItem]) -> Bool {
        !todos.isEmpty && todos.allSatisfy(\.done)
    }

    /// What the macOS menu bar shows while a block runs. The bar is shared with
    /// every other app's items, so the task name is clipped hard.
    static func menuLabel(task: String?, clock: String, maxChars: Int = 16) -> String {
        guard let task, !task.trimmingCharacters(in: .whitespaces).isEmpty else { return clock }
        return "\(clip(task, to: maxChars)) · \(clock)"
    }

    /// Clip to `maxChars`, preferring a word boundary when one falls in the last
    /// third — "Ship the scan history" reads better as "Ship the scan…" than as
    /// "Ship the scan h…".
    static func clip(_ s: String, to maxChars: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > maxChars, maxChars > 1 else { return t }
        let cut = t.prefix(maxChars - 1)
        if let space = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: space) > (maxChars * 2) / 3 {
            return String(cut[..<space]) + "…"
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
