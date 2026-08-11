import Foundation

/// Government holidays shown in the calendar (India national + Tamil Nadu state).
/// Surfaced on hover in `KMonthGrid`. This is the published **2026** Tamil Nadu list
/// (national gazetted + TN state holidays). A few lunar / Islamic dates can shift by a
/// day on moon-sighting — refresh this table each year.
enum Holidays {
    struct Holiday: Hashable {
        let name: String
        let national: Bool   // true = India-wide gazetted; false = Tamil Nadu / regional
    }

    static let byDate: [String: Holiday] = [
        "2026-01-01": Holiday(name: "New Year's Day", national: false),
        "2026-01-14": Holiday(name: "Thai Pongal", national: false),
        "2026-01-15": Holiday(name: "Thiruvalluvar Day", national: false),
        "2026-01-16": Holiday(name: "Uzhavar Thirunal", national: false),
        "2026-01-26": Holiday(name: "Republic Day", national: true),
        "2026-02-01": Holiday(name: "Thaipusam", national: false),
        "2026-03-19": Holiday(name: "Ugadi / Telugu New Year", national: false),
        "2026-03-21": Holiday(name: "Ramzan (Id-ul-Fitr)", national: true),
        "2026-03-31": Holiday(name: "Mahavir Jayanti", national: true),
        "2026-04-03": Holiday(name: "Good Friday", national: true),
        "2026-04-14": Holiday(name: "Tamil New Year & Ambedkar Jayanti", national: false),
        "2026-05-01": Holiday(name: "May Day", national: false),
        "2026-05-27": Holiday(name: "Bakrid (Eid al-Adha)", national: true),
        "2026-06-26": Holiday(name: "Muharram", national: true),
        "2026-08-15": Holiday(name: "Independence Day", national: true),
        "2026-08-26": Holiday(name: "Milad-un-Nabi", national: true),
        "2026-09-04": Holiday(name: "Krishna Jayanti", national: false),
        "2026-09-14": Holiday(name: "Vinayaka Chaturthi", national: false),
        "2026-10-02": Holiday(name: "Gandhi Jayanti", national: true),
        "2026-10-20": Holiday(name: "Ayudha Pooja", national: false),
        "2026-10-21": Holiday(name: "Vijayadashami", national: false),
        "2026-11-08": Holiday(name: "Deepavali", national: true),
        "2026-12-25": Holiday(name: "Christmas", national: true),
    ]

    /// Holiday name for a `yyyy-MM-dd` key, or nil.
    static func name(_ key: String) -> String? { byDate[key]?.name }
    static func holiday(_ key: String) -> Holiday? { byDate[key] }
}
