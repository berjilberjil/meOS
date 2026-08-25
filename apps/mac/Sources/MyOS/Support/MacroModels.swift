import SwiftUI

// Macro Intelligence — the shapes the dashboard reads, and the formatting rules
// that keep a rate from being displayed like a share price.

struct MacroPoint: Codable, Hashable { let d: String; let v: Double }

struct MacroDelta: Codable, Hashable {
    /// Absolute move in the metric's own unit; percent move against the prior value.
    let abs: Double
    let pct: Double
}

struct MacroMetric: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let country: String
    let unit: String
    /// Rates move in points, prices in percent — this decides which the UI shows.
    let kind: String            // rate | price | index
    let frequency: String
    let source: String
    let sourceUrl: String
    let priority: Int
    let value: Double?
    let asOf: String?
    let change1D: MacroDelta?
    let change7D: MacroDelta?
    let change30D: MacroDelta?
    let changeYTD: MacroDelta?
    let change1Y: MacroDelta?
    let history: [MacroPoint]
    let quality: String         // verified | estimated | delayed | unavailable
    let note: String?

    var isRate: Bool { kind == "rate" }
    var available: Bool { value != nil }
    var grade: MacroQuality { MacroQuality(rawValue: quality) ?? .unavailable }

    /// A metric moves the way its 1D change does — flat when there isn't one.
    var direction: Int {
        guard let d = change1D else { return 0 }
        if abs(d.abs) < 0.0001 { return 0 }
        return d.abs > 0 ? 1 : -1
    }
}

enum MacroQuality: String, Codable {
    case verified, estimated, delayed, unavailable

    var label: String {
        switch self {
        case .verified: return "Verified"
        case .estimated: return "Estimated"
        case .delayed: return "Delayed"
        case .unavailable: return "Unavailable"
        }
    }

    /// Estimated is deliberately not green. It is a number read off the web.
    var tint: Color {
        switch self {
        case .verified: return Palette.green
        case .estimated: return Palette.warning
        case .delayed: return Palette.blue
        case .unavailable: return Palette.faint
        }
    }
}

struct MacroScore: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let score: Int
    let state: String           // good | watch | risk | info
    /// The numbers the score was computed from, so it can be argued with.
    let inputs: [String]

    var tint: Color {
        switch state {
        case "good": return Palette.green
        case "watch": return Palette.muted
        case "risk": return Palette.warning
        default: return Palette.blue
        }
    }
}

struct MacroBrief: Codable, Hashable {
    struct Change: Codable, Hashable { let metric: String; let move: String }
    let changed: [Change]
    let why: String
    let matters: String
    let watch: [String]
    /// True when the "why" is inference rather than something the numbers show.
    let speculative: Bool
}

struct MacroSnapshot: Codable, Hashable {
    let date: String
    let generatedAt: String
    let metrics: [MacroMetric]
    let regime: [MacroScore]
    let brief: MacroBrief?

    func metric(_ id: String) -> MacroMetric? { metrics.first { $0.id == id } }
    var pulse: [MacroMetric] { metrics.filter { $0.priority == 0 } }
    /// Biggest movers first, ignoring anything with nothing to compare against.
    var movers: [MacroMetric] {
        metrics.filter { $0.change1D != nil }
            .sorted { abs($0.change1D?.pct ?? 0) > abs($1.change1D?.pct ?? 0) }
    }
}

/// How far back a chart looks. `max` is whatever the series has.
enum MacroRange: String, CaseIterable, Identifiable {
    case d1 = "1D", w1 = "1W", m1 = "1M", m3 = "3M", y1 = "1Y", y5 = "5Y", max = "MAX"
    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .d1: return 2
        case .w1: return 7
        case .m1: return 30
        case .m3: return 92
        case .y1: return 365
        case .y5: return 1826
        case .max: return nil
        }
    }

    /// The change this range corresponds to on a metric card.
    func delta(_ m: MacroMetric) -> MacroDelta? {
        switch self {
        case .d1: return m.change1D
        case .w1: return m.change7D
        case .m1, .m3: return m.change30D
        case .y1, .y5, .max: return m.change1Y
        }
    }
}

/// Number formatting for a screen where a yield and an index sit side by side.
enum MacroFormat {
    static func value(_ m: MacroMetric) -> String {
        guard let v = m.value else { return "—" }
        let body: String
        switch m.kind {
        case "rate": body = String(format: "%.2f", v)
        case "index": body = v >= 1000 ? grouped(v) : String(format: "%.2f", v)
        default: body = v >= 1000 ? grouped(v) : String(format: "%.2f", v)
        }
        if m.unit == "%" { return body + "%" }
        if m.unit == "₹" || m.unit == "$" { return m.unit + body }
        if m.unit.isEmpty { return body }
        return body + " " + m.unit
    }

    private static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v >= 10000 ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    /// One value with its unit, for a hover readout where there is no card.
    static func reading(_ v: Double, unit: String) -> String {
        let body = abs(v) >= 1000 ? grouped(v) : String(format: "%.2f", v)
        if unit == "%" { return body + "%" }
        if unit == "₹" || unit == "$" { return unit + body }
        if unit.isEmpty { return body }
        return body + " " + unit
    }

    /// Rates move in basis points; everything else in percent. Showing a repo
    /// rate as "+1.4%" when it went 6.50 → 6.59 is how people misread a chart.
    static func change(_ d: MacroDelta?, isRate: Bool) -> String {
        guard let d else { return "—" }
        if isRate {
            let bp = d.abs * 100
            return String(format: "%@%.0f bp", bp > 0 ? "+" : "", bp)
        }
        return String(format: "%@%.2f%%", d.pct > 0 ? "+" : "", d.pct)
    }

    static func tint(_ d: MacroDelta?) -> Color {
        guard let d, abs(d.abs) > 0.0001 else { return Palette.faint }
        return d.abs > 0 ? Palette.green : Palette.warning
    }

    /// A series clipped to a range, for the chart under a metric.
    static func series(_ points: [MacroPoint], range: MacroRange) -> [MacroPoint] {
        guard let days = range.days, let last = points.last else { return points }
        let cutoff = shift(last.d, by: -days)
        return points.filter { $0.d >= cutoff }
    }

    /// `yyyy-MM-dd` → Date. Charting the raw string puts every observation on
    /// its own category tick, which is what turned the axis into a smear.
    static func date(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(key.prefix(10)))
    }

    static func shift(_ key: String, by days: Int) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = c
        f.timeZone = c.timeZone
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: key), let moved = c.date(byAdding: .day, value: days, to: d) else { return key }
        return f.string(from: moved)
    }
}
