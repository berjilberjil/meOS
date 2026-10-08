import Foundation
import SwiftUI

enum FoldSpend {
    static func isNonSpend(_ category: String) -> Bool {
        let c = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return c == "returns" || c == "return" || c == "refund" || c == "refunds"
            || c == "cashback" || c == "interest" || c == "dividend"
    }
}

/// Rupee formatter for the Fold dashboard (en_IN grouping). Masks to "₹ ••••"
/// when privacy mode is on. A free function so it is unit-testable.
func foldINR(_ v: Double, hidden: Bool) -> String {
    if hidden { return "₹ ••••" }
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    f.maximumFractionDigits = 0
    return "₹" + (f.string(from: NSNumber(value: v.rounded())) ?? "0")
}


/// The snapshot Fold writes to `fold.json` (Application Support on Mac, bundled on iOS).
/// Also synced as `meos.fold` so the phone sees the same numbers the Mac just wrote.
struct FoldData: Codable, Equatable {
    var asOf: String = ""
    var currency: String = "INR"
    var netWorth: Double = 0
    var liquid: Double = 0
    var investments: Double = 0
    var debt: Double = 0
    var spentThisMonth: Double = 0
    var stocksValue: Double = 0
    var mfValue: Double = 0
    var changeValue: Double = 0
    var changePercent: Double = 0
    var changeLabel: String = ""
    var history: [Double] = []
    var banks: [Bank] = []
    var topSpends: [Spend] = []

    struct Bank: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var last4: String
        var balance: Double
        enum CodingKeys: String, CodingKey { case name, last4, balance }
        static func == (l: Bank, r: Bank) -> Bool {
            l.name == r.name && l.last4 == r.last4 && l.balance == r.balance
        }
    }
    struct Spend: Codable, Identifiable, Equatable {
        var id = UUID()
        var category: String
        var amount: Double
        enum CodingKeys: String, CodingKey { case category, amount }
        static func == (l: Spend, r: Spend) -> Bool {
            l.category == r.category && l.amount == r.amount
        }
    }

    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MeOS/fold.json")
    }

    /// Pre-rename location. Loads fall back to it once; saves clear it.
    private static var legacyFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("MyOS/fold.json")
    }

    /// The digits the user actually typed, with a leading country code removed.
    /// The field starts life holding "+91", so a plain digit count reached ten
    /// after eight keystrokes.
    static func nationalDigits(_ phone: String) -> String {
        // Strip on the field's own prefix, not on how many digits are present.
        // Counting was useless here: "+91" plus eight typed digits is exactly
        // ten, so the guard never fired at the size it existed to catch.
        var d = phone.filter(\.isNumber)
        if phone.hasPrefix("+91"), d.hasPrefix("91") { d.removeFirst(2) }
        else if d.count > 10, d.hasPrefix("91") { d.removeFirst(2) }
        return d
    }

    static func loadFromDisk() -> FoldData? {
        if let url = fileURL, let d = try? Data(contentsOf: url),
           let data = try? JSONDecoder().decode(FoldData.self, from: d) { return data }
        if let legacy = legacyFileURL, let d = try? Data(contentsOf: legacy),
           let data = try? JSONDecoder().decode(FoldData.self, from: d) { return data }
        return nil
    }

    static func load() -> FoldData? { loadFromDisk() }

    /// Remove this device's cached snapshot.
    ///
    /// Not part of the state blob, so logging out does not touch it otherwise —
    /// and the path is fixed, not per-account, so the next person to sign in on
    /// this Mac had the previous user's balances loaded straight back off disk
    /// and pushed into their own synced state by `healFoldSnapshot`.
    static func deleteFromDisk() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        if let legacy = legacyFileURL { try? FileManager.default.removeItem(at: legacy) }
    }

    static func save(_ data: FoldData) {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(data) { try? d.write(to: url, options: .atomic) }
        if let legacy = legacyFileURL { try? FileManager.default.removeItem(at: legacy) }
    }
}

/// A dashboard stat placeholder — a labelled empty value used only in the connect state.

enum CalMath {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }
    static func daysInMonth(year: Int, month: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: d) else { return 30 }
        return range.count
    }
    /// Weekday of the 1st — 0=Sun … 6=Sat.
    static func firstWeekday(year: Int, month: Int) -> Int {
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return cal.component(.weekday, from: d) - 1
    }
    static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
    static func monthName(_ month: Int, short: Bool = false) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        let syms = short ? f.shortMonthSymbols : f.monthSymbols
        return (syms?[max(0, min(11, month - 1))]) ?? ""
    }
    static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func date(fromKey key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    static func todayKey() -> String { dateKey(Date()) }
    /// (isSaturday, isSunday) for a `yyyy-MM-dd` key.
    static func weekend(_ key: String) -> (sat: Bool, sun: Bool) {
        guard let d = date(fromKey: key) else { return (false, false) }
        let wd = cal.component(.weekday, from: d)   // 1=Sun … 7=Sat
        return (wd == 7, wd == 1)
    }
    static func addMonth(year: Int, month: Int, delta: Int) -> (Int, Int) {
        var m = month + delta, y = year
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        return (y, m)
    }
}


// Today's focus — the daily crush list. Beyond a checklist it keeps three things:
// a focus timer that walks the day's tasks one at a time, a calendar record of how
// every past day went, and the streak that falls out of it.

// MARK: - Timer engine

/// Lives outside the view tree so a running session survives closing the sheet,
/// switching tabs, or the card redrawing.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    @Published private(set) var itemID: String?
    /// Kept alongside the id so the menu bar and the "time's up" notification can
    /// name the task without reaching into AppState.
    @Published private(set) var itemTitle = ""
    @Published private(set) var total = 0        // planned seconds
    @Published private(set) var remaining = 0
    @Published private(set) var running = false

    private var ticker: Timer?
    private var lastTick: Date?
    /// Seconds run since they were last written into the day plan.
    private var unbanked = 0

    var isActive: Bool { itemID != nil }
    var finished: Bool { isActive && remaining == 0 }
    var progress: Double { total > 0 ? Double(total - remaining) / Double(total) : 0 }

    var clock: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    func begin(_ item: FocusItem, minutes: Int) {
        stopTicking()
        itemID = item.id
        itemTitle = item.text
        total = max(60, minutes * 60)
        remaining = total
        unbanked = 0
        running = false
        resume()
    }

    func resume() {
        guard isActive, !running, remaining > 0 else { return }
        running = true
        lastTick = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
        // .common so the countdown keeps ticking while a sheet or menu is tracking.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard running else { return }
        step()                     // bank the partial second before stopping
        running = false
        stopTicking()
    }

    func add(minutes: Int) {
        guard isActive else { return }
        total += minutes * 60
        remaining += minutes * 60
        if !running { resume() }
    }

    func end() {
        stopTicking()
        itemID = nil
        itemTitle = ""
        running = false
        total = 0; remaining = 0
    }

    /// Seconds run since the last drain — the caller writes them into the day plan.
    func drainSpent() -> Int {
        let s = unbanked
        unbanked = 0
        return s
    }

    private func step() {
        let now = Date()
        // Wall-clock delta, so a slept Mac or a backgrounded phone doesn't lose time.
        let delta = max(0, Int(now.timeIntervalSince(lastTick ?? now).rounded()))
        lastTick = now
        guard delta > 0 else { return }
        // `min(delta, remaining + delta)` was a no-op: `remaining` is never
        // negative, so the cap was always `delta` itself. Shut the lid mid-block
        // and the timer's one catch-up tick banked the whole eight hours as
        // focused time — into synced state, into the day's total, into the
        // focused-minutes the AI is told about.
        unbanked += min(delta, remaining)
        remaining = max(0, remaining - delta)
        if remaining == 0 {
            running = false
            stopTicking()
            Haptics.success()
            SoundPlayer.drop()
            // The menu bar can run a block with no window on screen, so a sound
            // nobody is looking at isn't enough.
            FocusNotify.timesUp(task: itemTitle)
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        lastTick = nil
    }
}

// MARK: - The card

