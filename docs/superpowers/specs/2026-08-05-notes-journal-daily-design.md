# Notes + Journal — ready to use daily (design)

Date: 2026-08-05
Scope: macOS app (`apps/mac`). No backend schema change.

## Goal

Make the **Notes** and **Journal** features solid enough to live in every day. Not
new surface for its own sake — *reliability* + the one missing capability that
makes a journal a journal (looking back).

## Verified starting point (measured, not assumed)

- macOS app compiles clean (`BUILD SUCCEEDED`).
- Local Postgres `myos` DB running; schema applied; user `berjil` intact.
- Auth + per-user `key → JSON` state store round-trip verified end-to-end
  (register → login → PUT `myos.journal` / `myos.notes` → GET reads back).
- Mac app points at `http://localhost:5173` (`APIClient.baseURL`).

Conclusion: the code is **not broken**. The gaps are (1) the backend isn't
reachable unless a dev server is hand-started, (2) Journal is today-only, (3)
the Notes editor is unproven under daily hammering.

## Workstream A — Journal: full history + calendar

**Problem:** `JournalView` hardcodes `state.todayKey`. No way to open yesterday,
step back a week, or review the month. The data model already supports it —
`updateJournal(date:)` and `journalEntry(date:)` take an arbitrary date key.

**Design:**

- `JournalView` owns `@State private var viewedDate: String = state.todayKey`.
  Every card (mood, morning/night, wins/mistakes/lessons/gratitude) binds to
  `viewedDate` instead of `todayKey`. Writes go to `updateJournal(viewedDate)`.
- **Date navigator** in the header:
  - `‹` step one day back.
  - Center label: "Today" / "Yesterday" / "Wed, 5 Aug" — tap to open the month
    calendar popover.
  - `›` step one day forward, disabled when `viewedDate == today` (no future
    journaling).
  - A **"Today"** pill appears only when `viewedDate != today`; tap returns to today.
  - Keep the streak chip.
- **Month calendar popover:**
  - Standard month grid. Each day cell shows the day number.
  - A **dot** under days that have content; dot color follows the mood ramp when a
    mood is set, else a neutral brand tint. Today gets a ring; the viewed day is
    filled.
  - Month `‹ ›` to change month. Future days are dimmed and non-selectable.
  - Tap a day → set `viewedDate`, close popover.
- **AppState helpers (small, pure):**
  - `static func addDays(_ n: Int, to key: String) -> String` — date math on a
    `yyyy-MM-dd` key.
  - `func journalHasContent(_ date: String) -> Bool` — reuse the streak's "has
    content" test (morning/night/wins/mood non-empty).
  - `func journalMood(_ date: String) -> Int?`.

**Non-goals:** no journal search, no export, no rich text in reflections. Later.

## Workstream B — Notes: reliability pass (no new features)

**Problem:** the block editor is 558 lines of TextKit 1 that has never been driven
hard. Daily use will expose caret/markdown/save edge cases.

**Design:** treat it as debugging, not building. Drive the real app through a fixed
matrix; fix only what actually breaks. Matrix:

- Create → type title + body → close → reopen: content intact (save-on-close).
- Block markdown at line start: `# `, `## `, `### `, `- `, `* `, `1. `, `[] `,
  `> `, ` ``` `, `---`.
- Inline markdown: `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`.
- Enter mid-list continues the list; Enter on an empty list item exits it.
- Backspace at block start (reset styled block → paragraph; merge into previous).
- Slash menu: `/` opens, query filters, selection applies, caret lands right.
- `Cmd-B / I / E` toggles on selection and for subsequent typing.
- Switch tab away/back and full relaunch: content persists (server + cache).
- Pin/unpin, delete (with confirm), search by title/body.
- Empty-note cleanup: closing an untouched empty note removes it.

**Deliverable:** a short bug list with the fix for each, applied. No feature adds
unless a fix naturally requires one.

## Workstream C — Daily-use reachability (recommended)

**Problem:** the app is only usable while `npm run dev` runs. "Ready daily" isn't
real until the backend is always on.

**Recommended:** a user LaunchAgent (`~/Library/LaunchAgents/com.berjil.myos.backend.plist`)
that starts the SvelteKit backend on login and keeps it alive. Postgres already
auto-starts (`brew services`). Result: open `MyOS.app`, it works — offline, no
cloud, no cost, no secrets to manage. Cloud (Netlify + Supabase) stays the option
for when an iPhone client appears; not needed for a Mac-only tool now.

**Status:** pending the owner's go/no-go (deflected twice; decide after using the
running app).

## Order of work

1. Journal history + calendar (highest value, lowest risk — pure UI).
2. Notes reliability pass (drive + fix).
3. Daily-use LaunchAgent (if approved).

## Risks

- TextKit editor fixes can regress each other; verify the full matrix after each fix.
- Calendar date math must be timezone-stable — reuse the existing POSIX/gregorian
  `DateFormatter` path in `AppState`, never `Calendar.current` for key strings.
