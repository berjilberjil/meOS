import Foundation

// MARK: - Kinds

/// What kind of thing is sitting in the bin.
///
/// The raw values are a wire format. They travel inside the synced `myos.trash`
/// blob and they are what a restore dispatches on, so renaming one strands
/// everything already deleted under the old name — it would still be in the bin
/// and the Restore button would silently do nothing.
///
/// Deliberately only the things you would describe as *deleted*. Pulling one set
/// out of a workout or one food off a meal is an edit, and a bin that fills up
/// with edits is a bin you stop opening — which costs you the one case it exists
/// for, the note you meant to keep.
enum TrashKind: String, Codable, CaseIterable, Hashable, Sendable {
    case note, event, belonging, watch, todo, scan
    case chatThread, progressPhoto
    case food, exercise, program

    /// Singular, for a row.
    var label: String {
        switch self {
        case .note:          return "Note"
        case .event:         return "Event"
        case .belonging:     return "Stuff"
        case .watch:         return "Video"
        case .todo:          return "To-do"
        case .scan:          return "Scan"
        case .chatThread:    return "Chat"
        case .progressPhoto: return "Photo"
        case .food:          return "Food"
        case .exercise:      return "Exercise"
        case .program:       return "Program"
        }
    }

    /// Plural, for a section header.
    var plural: String {
        switch self {
        case .belonging:     return "Stuff"          // already plural
        case .watch:         return "Videos"
        case .chatThread:    return "Chats"
        case .progressPhoto: return "Photos"
        default:             return label + "s"
        }
    }

    var symbol: String {
        switch self {
        case .note:          return "note.text"
        case .event:         return "calendar"
        case .belonging:     return "shippingbox.fill"
        case .watch:         return "play.rectangle.fill"
        case .todo:          return "checkmark.circle.fill"
        case .scan:          return "viewfinder"
        case .chatThread:    return "bubble.left.fill"
        case .progressPhoto: return "photo.fill"
        case .food:          return "fork.knife"
        case .exercise:      return "figure.strengthtraining.traditional"
        case .program:       return "list.bullet.rectangle"
        }
    }

    /// The order sections appear in the bin — the things you are most likely to
    /// have deleted by accident, first.
    var rank: Int {
        switch self {
        case .note: return 0
        case .event: return 1
        case .progressPhoto: return 2
        case .belonging: return 3
        case .todo: return 4
        case .watch: return 5
        case .scan: return 6
        case .chatThread: return 7
        case .program: return 8
        case .exercise: return 9
        case .food: return 10
        }
    }
}

// MARK: - Entry

/// One deleted thing, kept whole so it can be put back exactly as it was.
///
/// The object itself rides along as JSON in `payload` rather than as a typed
/// field per kind. Twelve optional properties on one struct would mean twelve
/// more things for `applyRemote` to diff and a migration every time a module
/// gained a field; a blob means the bin never needs to understand what it is
/// holding, only how to hand it back.
struct TrashEntry: Codable, Identifiable, Hashable, Sendable {
    /// This entry's own id. Not the item's — delete a note, restore it, delete it
    /// again and those are two different bin entries with the same `itemID`.
    var id: String
    /// The id the object had, and will have again when it goes back.
    var itemID: String
    var kind: TrashKind
    /// What the row reads. Resolved at delete time, because the thing that could
    /// name it is gone by the time the bin is drawn.
    var title: String
    var subtitle: String
    /// `yyyy-MM-dd'T'HH:mm:ss`, same shape as every other stamp in the app.
    var deletedAt: String
    /// JSON of the original object.
    var payload: String
    /// The day key a to-do or a journal entry belonged to. Without it there is
    /// nothing to put a restored to-do back *into*.
    var context: String?
    /// R2 objects this entry is keeping alive. Deleting an event used to drop its
    /// photos from the bucket immediately, which made a restore a restore of the
    /// words and not the pictures. They are now released when the entry is purged.
    var mediaKeys: [String]

    init(id: String = UUID().uuidString.lowercased(),
         itemID: String,
         kind: TrashKind,
         title: String,
         subtitle: String = "",
         deletedAt: String,
         payload: String,
         context: String? = nil,
         mediaKeys: [String] = []) {
        self.id = id; self.itemID = itemID; self.kind = kind
        self.title = title; self.subtitle = subtitle
        self.deletedAt = deletedAt; self.payload = payload
        self.context = context; self.mediaKeys = mediaKeys
    }

    enum CodingKeys: String, CodingKey {
        case id, itemID, kind, title, subtitle, deletedAt, payload, context, mediaKeys
    }

    /// Lenient, like every other model here: an entry written by an older build
    /// must still decode rather than take the whole bin down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        itemID    = try c.decodeIfPresent(String.self, forKey: .itemID) ?? ""
        kind      = (try? c.decode(TrashKind.self, forKey: .kind)) ?? .note
        title     = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle  = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt) ?? ""
        payload   = try c.decodeIfPresent(String.self, forKey: .payload) ?? ""
        context   = try c.decodeIfPresent(String.self, forKey: .context)
        mediaKeys = (try? c.decodeIfPresent([String].self, forKey: .mediaKeys)) ?? []
    }

    /// The `yyyy-MM-dd` the delete happened on.
    var deletedDay: String { String(deletedAt.prefix(10)) }

    /// A title that is never empty — an untitled note in the bin still has to be
    /// something you can point at.
    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled \(kind.label.lowercased())" : t
    }
}

// MARK: - Encoding the thing itself

extension TrashEntry {
    /// The object, as the JSON text that goes in `payload`.
    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The object back out. `nil` when the payload was written by a build whose
    /// shape no longer decodes — the caller must leave the entry in the bin
    /// rather than drop it, because a restore that cannot restore must not also
    /// destroy the only copy.
    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Retention

/// How long the bin holds on, and the arithmetic behind "27 days left".
///
/// Pure and day-based on purpose. Wall-clock deltas would make "30 days" mean
/// 30×24 hours from the minute of the delete, so a thing deleted at 11pm would
/// leave a day earlier than one deleted at 1am the next morning, and the number
/// on the row would tick over at a different time for every item in the bin.
enum TrashRetention {
    /// The window, in days.
    static let days = 30

    /// The day an entry is purged on.
    static func purgeDay(_ entry: TrashEntry) -> String? {
        let day = entry.deletedDay
        guard EventVoice.dayDelta(from: day, to: day) == 0 else { return nil }
        return EventVoice.key(addingDays: days, to: day)
    }

    /// Whole days before this entry goes. 0 means it goes today; negative means
    /// it is already overdue.
    ///
    /// A stamp that will not parse reports the full window. It is the safe
    /// direction to be wrong in: a bad stamp should cost you a row that lingers,
    /// never a note that vanishes.
    static func daysLeft(_ entry: TrashEntry, todayKey: String) -> Int {
        guard let purge = purgeDay(entry),
              let delta = EventVoice.dayDelta(from: todayKey, to: purge) else { return days }
        return delta
    }

    static func isExpired(_ entry: TrashEntry, todayKey: String) -> Bool {
        daysLeft(entry, todayKey: todayKey) <= 0
    }

    /// The bin, split into what stays and what the sweep takes.
    static func split(_ entries: [TrashEntry], todayKey: String)
    -> (kept: [TrashEntry], expired: [TrashEntry]) {
        var kept: [TrashEntry] = [], expired: [TrashEntry] = []
        for e in entries {
            if isExpired(e, todayKey: todayKey) { expired.append(e) } else { kept.append(e) }
        }
        return (kept, expired)
    }

    /// How a row says how long it has left.
    static func remainingPhrase(_ entry: TrashEntry, todayKey: String) -> String {
        let left = daysLeft(entry, todayKey: todayKey)
        switch left {
        case ..<0:  return "going now"
        case 0:     return "goes today"
        case 1:     return "1 day left"
        default:    return "\(left) days left"
        }
    }

    /// How a row says when it was deleted.
    static func deletedPhrase(_ entry: TrashEntry, todayKey: String) -> String {
        guard let ago = EventVoice.dayDelta(from: entry.deletedDay, to: todayKey) else {
            return "deleted"
        }
        switch ago {
        case ..<0:  return "deleted"        // a stamp from the future; say nothing clever
        case 0:     return "deleted today"
        case 1:     return "deleted yesterday"
        default:    return "deleted \(ago) days ago"
        }
    }
}
