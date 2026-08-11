# Events → Memory Log — redesign spec

**Date:** 2026-08-11
**App:** `apps/mac` (native SwiftUI macOS app)
**Owner:** Berjil

## Goal

Reframe the **Events** tab from an *upcoming to-do timeline* into a **memory log**: a
place to log life events — past, present, or future — frequently and lightly, so they
accumulate into a browsable memory. Each event carries **photos/videos + a note** and
**custom tags**. The calendar is the primary surface; a list of events is always visible
below it.

## Current state (what exists today)

- `Views/EventsView.swift` (520 lines) — three tabs **List / Month / Year**.
  - **List** = an upcoming timeline grouped into buckets (Overdue / Today / This week /
    This month / Later) with "in N days" countdowns, a `done` checkbox per row, and a
    collapsible **Past & done** archive.
  - **Month** = calendar grid; the day list appears **only when a day is selected**, and
    tapping a day just toggles that day's card.
  - **Year** = a 12-mini-months grid (`LazyVGrid` of compact `KMonthGrid`s). No list below.
- `EventItem` (`Support/Models.swift:728`): `id, date (yyyy-MM-dd), title, category
  (EventCategory enum), note, special, done`. Lenient `Codable` decoder (missing fields
  tolerated).
- `EventCategory` (`Models.swift:712`): fixed enum `travel/family/work/personal/milestone/
  reminder/other`; color + SF Symbol hardcoded in `EventsView.swift:497`.
- No media of any kind on events.
- `AppState` (`Support/AppState.swift`): `@Published var events`, `addEvent / updateEvent /
  deleteEvent / toggleEventDone`, derived `sortedEvents / doneEvents / nextEvents`, and
  `daysUntil`. Persisted under `StateKey.events = "myos.events"`; whole state is one
  zero-knowledge-encrypted, fully-synced blob.
- `KMonthGrid` (`Views/CalendarComponents.swift:54`): `init(year, month, selected?, compact,
  dot: (String)->Color?, onTap: (String)->Void)`. Monday-first, colored dot per day with
  content, ring on today, green selected day.

## Product decisions (settled with owner)

1. **Remove `done` / completion entirely.** A memory isn't "done." No checkbox, no
   Overdue/Today buckets, no "in N days" pressure, no Past & done archive.
2. **Multiple tags per event** (chips), not a single category.
3. **Images + video in v1, with a video size limit.**
4. Keep the **★ Special** flag to highlight big memories.
5. **Drop the List tab.** Tabs = **Month · Year** only. In both, the event list below is
   **always visible** (never hidden by selection state).
6. **Clicking any date → immediately opens the Add-event editor** with that date preset.
7. Custom tags = **name + SF Symbols icon + color** (native equivalent of "Lucide"; seed the
   current 7 as editable defaults).

## Non-goals (explicitly deferred)

- macOS **menu bar** (`MenuBarExtra`) quick-log — separate future spec.
- macOS **widget** (WidgetKit) — separate future spec.
- Reminders/notifications for future events.
- Rich-text notes (notes stay plain text + a media grid).

## Data model changes

### `EventTag` (new)

```swift
struct EventTag: Codable, Identifiable, Hashable {
    var id: String            // uuid, lowercased
    var name: String
    var symbol: String        // SF Symbol name, e.g. "airplane"
    var colorHex: String      // "#RRGGBB"
    var builtIn: Bool = false // seeded defaults; user tags = false
}
```

- Seeded defaults on first run (mirrors today's 7): Travel `airplane` blue, Family
  `house.fill` flame, Work `briefcase.fill` amber, Personal `person.fill` brand, Milestone
  `flag.fill` purple, Reminder `bell.fill` ice, Other `calendar` muted. `builtIn = true`.
- Built-in tags are editable (name/color/symbol) but **not deletable**; deleting a custom
  tag removes its id from all events.

### `EventMedia` (new) — mirrors the note-block base64 pattern (`BlockDocument.swift:59`)

```swift
struct EventMedia: Codable, Identifiable, Hashable {
    var id: String
    var kind: Kind            // image | video
    var data: String          // base64 (no data: prefix). image: JPEG; video: mp4/mov
    var poster: String?       // video only: base64 JPEG first-frame thumbnail
    enum Kind: String, Codable { case image, video }
}
```

- **Images:** reuse the existing downscale + JPEG + base64 pipeline (`Views/BlockEditor/
  BlockMedia.swift` `ImageMedia`). Same max-dimension downscale.
- **Video:** on pick, run `AVAssetExportSession` to compress to ≤540p H.264, generate a
  first-frame poster (downscaled JPEG), then enforce a **hard cap of 15 MB** on the encoded
  bytes; over the cap → reject with an inline message. Store base64 inline like images.
  Rationale: the whole app state is one encrypted, fully-synced blob, so inline video must
  stay bounded. (Cap is a single constant, easy to tune.)

### `EventItem` (extend, back-compat)

Add:
```swift
var tagIDs: [String] = []       // replaces single `category`
var media: [EventMedia] = []
```
- Keep `category` and `done` **decodable** (do not remove the coding keys) so old data loads.
- Migration on load: if `tagIDs` is empty but a legacy `category` decoded, map it to the
  seeded built-in tag id for that category. `done` is ignored (dropped from UI).
- Extend the lenient `init(from:)` with `decodeIfPresent` for `tagIDs`/`media`.

### `AppState` / sync wiring

- Add `@Published var eventTags: [EventTag] = []`, seeded if empty on load.
- New `StateKey.eventTags = "myos.eventTags"`; add to the persist tuple list
  (`AppState.swift:229–234`) and the snapshot `add(...)` block (`~324`).
- Extend the `AppData`/state Codable struct (`Models.swift:~873, ~914`) with
  `var eventTags: [EventTag]?` and load it in `AppState` init (`~101`).
- Tag CRUD: `addTag / updateTag / deleteTag(id)` (delete also scrubs the id from every
  event, then `push`es both keys).
- Event methods: `addEvent(date:title:tagIDs:note:special:media:)`,
  `updateEvent(_:)`, `deleteEvent(id:)`. Remove `toggleEventDone`.
- **Keep** `daysUntil` (pure date math) and **redefine** `nextEvents` to be date-based:
  future events (`date >= todayKey`) sorted ascending, `.prefix(2)` — TodayView depends on
  both (`Views/TodayView.swift:35,73,102`).
- Remove `doneEvents`; rework `sortedEvents` → chronological, no `done` filter (or inline
  where used).

## UX / view changes (`EventsView.swift`)

- `Mode` enum: drop `.list` → `{ month, year }`. Default `month`.
- **Delete** `listView`, `timeline`, `pastSection`, `EventBucket`, and the `done` toggle
  button + strikethrough in `EventRow`. Remove the "Add event" reliance on buckets.
- **Month tab:**
  - Calendar `Card` on top (unchanged header/grid).
  - `KMonthGrid.onTap` → open `EventEditor` with `presetDate` for that day (no select toggle).
    Optionally still set `selectedDay` to visually highlight + scroll the list to that day.
  - **Always-visible list below:** every event whose `date` falls in `viewYear/viewMonth`,
    sorted by date ascending, grouped by day (day header + rows). Never hidden. Empty month
    → a light "Nothing logged this month yet — tap a day to add a memory." (still shows the
    calendar + omnibox above).
  - `dayDot`: use the first tag's color (special → amber), same as today.
- **Year tab:**
  - Keep the 12-mini-months grid on top (already built); tapping a mini-month → `mode =
    .month` at that month.
  - **Add an always-visible list below** of that year's events (grouped by month → day).
- Top-right: keep **★ / Segmented(Month·Year) / + Add event**.

### Editor (`EventEditor`) changes

- Replace single-select category chips with **multi-select tag chips** over `state.eventTags`
  (toggle on/off; `tagIDs` is a Set-like array), plus a **"＋ New tag"** affordance opening
  the tag manager.
- Add a **media section**: a grid of thumbnails (image = the image, video = poster with a
  play glyph) + an "Add photo/video" button (`ImageDropZone`-style picker). Each thumbnail
  has a remove control. Videos show the size; over-cap picks are rejected inline.
- Keep title, date (popover calendar), ★ Special, note (plain multiline).
- Save writes `tagIDs` + `media` through the updated `AppState` methods.

### Tag manager (new small sheet/popover)

- List existing tags (built-in + custom) with their icon + color.
- Add/edit: name field, **SF Symbols picker** (a curated grid — a fixed array of ~40–60
  symbol names spanning life categories; searchable if trivial), color swatch row (reuse
  `Palette` accent colors).
- Delete (custom only) with hold-to-confirm; scrubs the id from all events.

## Files touched

- `Support/Models.swift` — `EventTag`, `EventMedia`, extend `EventItem`, add `eventTags` to
  state struct, `StateKey.eventTags`.
- `Support/AppState.swift` — publish/seed `eventTags`, tag CRUD, event method changes,
  `nextEvents` redefinition, remove `doneEvents`/`toggleEventDone`, sync wiring.
- `Views/EventsView.swift` — drop List/buckets/done, always-visible month & year lists,
  click-to-create, multi-tag + media editor, tag color/icon now read from `EventTag`.
- `Views/CalendarComponents.swift` — no API change expected (reuse `dot`/`onTap`).
- New: a small **TagManager** view + **SF Symbols picker** (can live in `EventsView.swift` or
  a new `Views/EventTagManager.swift`) and a media helper for video (`AVAssetExportSession`
  compress + poster) — extend `BlockMedia.swift` or a new `Support/VideoMedia.swift`.
- `Views/TodayView.swift` — verify it still compiles against redefined `nextEvents`; no
  behavior change intended (drop any `done` assumptions if present).

## Testing

- Unit: legacy `EventItem` JSON (with `category`/`done`, no `tagIDs`/`media`) decodes and
  migrates `category` → seeded tag id; `done` ignored.
- Unit: `eventTags` seeds exactly the 7 built-ins on empty state; deleting a custom tag
  scrubs its id from events.
- Unit: video over the 15 MB cap is rejected; under-cap stores base64 + poster.
- Unit: `nextEvents` returns future-dated events ascending (independent of any `done`).
- Manual: click a day → editor opens with that date; add multi-tag + photo + video; month &
  year lists stay visible with events grouped by day/month; Year mini-month tap → Month.

## Rollout / migration notes

- Additive & back-compat: no destructive schema change; old events load and gain a tag.
- One encrypted synced blob — video cap keeps sync payloads bounded.
- Menu bar + widget remain future specs and are unaffected.
