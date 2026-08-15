# MyOS — Polish, Notifications & Food/Fitness Redesign — Design

**Date:** 2026-08-15
**Status:** Design (awaiting review)
**Scope:** Native app monorepo (`apps/mac`, `apps/ios`, shared `Support/`, and the `apps/web` chat backend).

## Overview

A batch of ~15 requested changes, grouped into four buildable phases. Phases
are built in order because later phases depend on the primitives introduced in
earlier ones (the mood control and food/fitness screens use the haptics and
confirm/delete gestures from Phase A). Each phase gets its own implementation
plan after this design is approved.

**Guiding facts about the codebase** (from the current source):

- Anything in `apps/mac/Sources/MyOS/Support/` is compiled into **both** the
  mac and iOS targets (`apps/ios/project.yml`). Shared helpers (haptics,
  privacy flag, notifications, confirm gestures) live there and are written
  once. `MainView`, `SettingsView`, `NotesView`, `EventsView` are **per
  platform**.
- Persistence has two lanes: **device-local config** → `UserDefaults`
  (`ThemeStore`, `AgentConfig`, `BiometricLock` are the precedents), and
  **synced user data** → `AppState.push(StateKey.x, value)` (encrypted KV, one
  `myos.*` key per domain). New *settings* use the UserDefaults lane; new
  *data* uses the StateKey lane.
- Settings cards follow the `AppearanceCard.swift` shape: a `Card { }` observing
  a `.shared` `ObservableObject`, mutating through a store or `AppState` method,
  added to both `SettingsView` bodies.

## Cross-cutting decisions (locked with owner)

1. **Build order:** A → B → C → D, one phase at a time, spec/plan per phase.
2. **Chat 502 fix:** stream the reply (server SSE + Swift client renders live),
   with a Netlify function `maxDuration` bump as a safety net.
3. **Food/fitness logging model:** set a 7-day food + workout plan; each day the
   plan pre-fills, and per meal/workout the user **ticks "ate it / did it"**
   (logs the planned macros), **edits** to what they actually ate, or
   **scans/adds** the real food. A meal can also be **skipped**. This is a
   *planned → confirmed* flow with per-day overrides that never mutate the
   weekly template. It maps onto the existing `nutrition.mealPlan` (template)
   vs `nutrition.log` (actual) split.
4. **Hidden notes:** reuse the existing per-note `locked` flag as "hidden."
   Locked notes are hidden from the list; a 5-tap gesture + Face ID reveals
   them for the session; a 2-tap gesture creates a new note.
5. **Confirm gestures:** slide-to-confirm for commits (log, apply plan, save),
   hold-to-delete for deletions (the existing `HoldToConfirmButton`), applied
   app-wide.
6. **Notifications:** local, on both iOS and mac; times editable in Settings;
   on by default once permission is granted.

---

## Phase A — Interaction primitives

Foundational, cross-cutting UI primitives that B and D consume.

### A1. Haptics helper

New `Support/Haptics.swift` (shared):

```
enum Haptics {
    static func tap()        // light impact / generic press
    static func selection()  // value stepped (slider stop, segment change)
    static func success()    // commit succeeded (send, confirm, log)
    static func warning()    // destructive confirmed (delete)
}
```

- iOS: `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`,
  `UINotificationFeedbackGenerator`. Generators are prepared lazily and reused.
- macOS: `NSHapticFeedbackManager.defaultPerformer.perform(...)` (fires only on
  a Force Touch trackpad; a no-op otherwise, which is fine).
- Platform split via `#if os(macOS)` / `#else`, following the precedent in
  `VaultViews.swift`.

### A2. App-wide wiring

- Add a `Haptics.tap()` call inside the shared button styles in
  `SharedComponents.swift` (`KPrimaryButtonStyle`, `KSoftButtonStyle`,
  `KIconButtonStyle`, …) so ordinary taps feel haptic everywhere without
  per-call-site edits.
- Explicit calls at key moments: tab switch (both `MainView`s), mood slider
  stop (`selection`), chat send (`tap`) and reply received (`success`),
  slide-to-confirm completion (`success`), hold-to-delete completion
  (`warning`).

### A3. Slide-to-confirm

New `SlideToConfirm` in `SharedComponents.swift`, mirroring the existing
`HoldToConfirmButton` API so both feel consistent:

- A track with a draggable thumb; dragging the thumb to the end fires `action()`
  once and emits `Haptics.success()`. Releasing early snaps back.
- Extracted threshold/progress logic into a tiny pure struct so it is unit
  testable (fires exactly once at ≥ threshold; resets on cancel).
- Adoption: commit actions (Fitness "log today", apply/copy plan, editor
  "Save") use `SlideToConfirm`; destructive actions (delete food/exercise/plan
  row, resets) use the existing hold-to-delete popover — including the fitness
  delete buttons that currently delete with an unconfirmed `xmark`.

### A testing

- Unit-test the slide-confirm progress model (threshold fire-once, cancel
  reset). Haptics are side-effecting and are left untested (no observable
  return); the helper is a thin platform shim.

---

## Phase B — Quick wins & fixes

Independent, mostly small changes. Each is isolated.

### B1. Fold privacy toggle

- New device-local flag `myos.fold.hideNumbers` via a shared
  `PrivacyStore.shared : ObservableObject` (UserDefaults lane), or `@AppStorage`
  if a store proves unnecessary.
- An eye / eye-slash toggle in the `FoldView` header. When on, every rupee value
  is masked. The cleanest hook is the single `inr(_:)` formatter
  (`FoldView.swift`), which returns `"₹ ••••"` when hidden. Additionally hide the
  `Sparkline`, the `changeChip` percentage, and bank `last4`.
- Persists per device; independent of any auth state.

### B2. Launch / default tab

- New `myos.launchTab` (UserDefaults, NavTab raw). Both `MainView`s initialize
  their `@State tab` from it instead of hardcoding `.today`.
- A picker in Settings (both platforms). The mac picker offers all 9 tabs; the
  iOS picker offers only its 5 visible tabs (today, fold, fitness, journal,
  notes). Invalid stored values fall back to `.today`.

### B3. Journal "Today" button placement

- In the iOS `[Events | Journal]` header row (`JournalView.swift`, `#if os(iOS)`),
  move the "Today" pill to the **right end of the same row** as the segmented
  control, instead of stacking it under the segmented control in the journal
  sub-view. Shown only when the viewed date is not today.

### B4. Mood slider

- Replace `MoodPicker` (a row of 1–5 tap buttons) with a horizontal **slider**
  with 5 stops mapped to the existing scale `1–5` → `["Rough","Low","Okay",
  "Good","Great"]`. Storage stays `entry.mood: Int?`.
- Default display position = **"Rough"** (the user slides up to reflect the
  day). Each stop change emits `Haptics.selection()`. The current word renders
  under the thumb, tinted by the existing red→green `moodTint`.

### B5. Events: remove "+ New event", double-tap Journal tab to add

- Remove the "New event" button from the **iOS** `EventsView` header (keep the
  mac calendar's tap-a-day-to-add affordance).
- Double-tapping the **Journal bottom tab** opens the new-event editor. Detected
  via a custom `TabView` selection binding that recognizes re-selection of the
  already-active Journal tab (with a short double-tap window), then presents the
  `EventEditorSheet(event: nil)`.

### B6. Notes: 5-tap reveal (Face ID) + 2-tap new note

- Reuse the `Note.locked` flag as "hidden": locked notes are filtered out of the
  notes list by default (both platforms).
- On the "Notes" title: a 5-tap gesture triggers `BiometricLock` (Face/Touch ID)
  and, on success, reveals locked notes for the session (a `revealed` flag reset
  when leaving Notes). A 2-tap gesture creates a new note (`addBlockNote`).
- iOS gains a proper reveal path (today its list merely hides the *preview* of
  locked notes and still opens them); mac already has a session-unlock set to
  build on.

### B7. Chat 502 — streaming

- **Server** (`apps/web/src/routes/api/chat/+server.ts`): replace blocking
  `generateText` with `streamText` and return a streaming response (SSE / data
  stream). Keep the same auth gate, message bounding, model routing, and system
  prompt. Add a `maxDuration` for the chat function (Netlify config) as a
  backstop.
- **Client** (`apps/mac/Sources/MyOS/Support/APIClient.swift`): add a streaming
  `chatStream` using `URLSession.bytes(for:)`, yielding text deltas.
  `AppState.sendChat` appends an empty assistant turn and grows it as deltas
  arrive; `chatBusy` clears on stream end. Errors still surface via `chatError`.
- Both platforms benefit (shared files). Chat send/reply haptics come from
  Phase A.

### B8. Food scan 400

- The `api/parse-image` endpoint returns 400 only when the `images` array is
  empty — a client-side capture/encoding bug, not the AI. Reproduce the iOS
  camera / Photos path in `ImageDropZone.swift` + `AppState.analyzeFood`, fix
  the empty/nil base64 case, and confirm `mediaType` matches what the endpoint
  expects. Scanned macros are already editable in `FoodScanReviewSheet`; verify
  and keep that. (Deeper scan UX lives in Phase D.)

### B testing

- Unit-test: privacy masking string, launch-tab fallback for invalid values,
  mood scale↔word mapping. View/gesture behavior is verified by building and
  running both targets.

---

## Phase C — Notifications

Greenfield local notifications on both platforms.

### C1. Scheduler

- New `Support/Notifications.swift` (shared): request `UNUserNotificationCenter`
  authorization; schedule daily-repeating notifications from a settings model;
  reschedule on change; cancel all when disabled.
- Default reminders (all editable): **06:00** "Log your weight + journal, check
  MyOS", **08:00** breakfast, **12:30** lunch, **16:00** workout, **19:00**
  dinner.
- Reminder config in `UserDefaults` (device-local, matching the settings lane) —
  each reminder = enabled flag + time-of-day.

### C2. Settings UI

- New shared `NotificationsCard` (AppearanceCard shape): master enable/permission
  row + a time picker per reminder. Added to both `SettingsView`s.

### C3. Platform wiring

- Local notifications need no push entitlement (`aps-environment` is only for
  remote push). Just request authorization on first enable.
- Meal/workout reminder taps deep-link into the app at the relevant Fitness
  meal/workout (ties into Phase D's tick flow). Kept minimal.

### C testing

- Unit-test the schedule-building logic (settings → the set of daily triggers,
  including disabled reminders producing none). Authorization and delivery are
  verified on-device.

---

## Phase D — Food + Fitness redesign

The largest phase: reshape the existing food/fitness UI around the plan → tick
flow, make the weekly planner big and legible, add copy-day for food, and clean
up the scan → editable-macros path. Most of the data model already exists.

### D1. Information architecture

Today `FitnessView` has four subs (`today / food / workout / body`), with weekly
planning buried in a cramped `MealPlanSheet` and inside `WorkoutView`. The user's
complaint: food and workout each repeat the same "show all / add new / plan"
pattern, and the plan UI is tiny.

Proposed structure (details refined in the Phase D plan):

- **Today** — the day's plan-driven checklist: each meal (breakfast/lunch/dinner/
  snacks) and the day's workout shown as a card that is one of: *unconfirmed*
  (planned items shown ghosted, with **tick / edit / scan / skip**), *logged*
  (actual items + macros, checkmarked), or *skipped* (struck through). This is
  the primary daily surface.
- **Plan (week)** — a full-screen, legible 7-day planner (replacing the tiny
  sheet) for both meals and workouts, with **copy this day → all days / pick
  days** for food (workout copy-day already exists — unify the interaction).
- **Library** — browse all foods / all exercises; add custom (the "show all /
  add new" that food and workout both need), unified in look.
- **Body** — unchanged anatomy map.

### D2. Data model (plan → confirmed)

Existing (keep): `NutritionState { customFoods, log:[date:MealLog],
mealPlan:[weekday:[meal:[PlanItem]]] }`; `MealLog { meals:[meal:[PlanItem]] }`;
`TrainingState { customExercises, weekPlan:[weekday:WorkoutDayPlan] }`.

Additions:

- `MealLog.skipped: [String]` — meal raws the user intentionally skipped that
  day, to distinguish *skipped* from *not-yet-ticked*.
- **Tick "ate it"** = copy that meal's plan items (for the day's weekday) into
  `log[date].meals[meal]`. **Edit** = mutate `log[date].meals[meal]` directly.
  **Scan/add** = append parsed foods to `log[date].meals[meal]`. **Skip** = add
  the meal raw to `log[date].skipped`.
- A meal's display state derives from the log: has items → logged; in `skipped`
  → skipped; else → unconfirmed (show the plan template).
- Workout daily state: add a per-date workout log
  `TrainingState.dayLog: [date: WorkoutDayLog]` where
  `WorkoutDayLog { done: Bool, skipped: Bool, items: [PlanExercise]? }` (nil
  items = "did it as planned"; non-nil = edited actual). Mirrors the meal model.

The weekly `mealPlan` / `weekPlan` templates are **never** mutated by daily
ticks/edits/skips — only the per-date `log` / `dayLog` change.

### D3. Weekly planner UI

- Replace `MealPlanSheet` (cramped day-segment × 4 meals) with a full-screen
  planner: a clear day selector (or 7 columns), roomy rows, add/remove per meal.
- **Copy a day → all days / specific days** for food (parallel to the workout
  copy-day menu). One shared copy-day interaction for both meals and workouts.

### D4. Scan → editable macros

- Fix the empty-`images` 400 (also addressed in B8), and make the scan entry
  reachable from a meal card's **scan** action so a scanned food lands directly
  in that meal.
- `FoodScanReviewSheet` already lets the user edit extracted macros before
  logging; keep and polish it. Slide-to-confirm on "Add & log".

### D5. Confirm/delete gestures

- Fitness delete actions (food row, plan item, exercise, custom food/exercise)
  adopt hold-to-delete. Commit actions (tick "ate it", "log today", apply plan,
  copy day, save editor) adopt slide-to-confirm. Both from Phase A.

### D testing

- Unit-test the plan→log derivation: tick copies template into log; edit/scan
  mutate only the day; skip marks skipped; templates remain unchanged; a day's
  macro total sums logged (not planned) items. Reuse the existing `Nutrition`
  pure-logic test style.

---

## Out of scope (YAGNI)

- Remote/push notifications, a notification server. (Local only.)
- HealthKit auto-sync for steps/weight/workouts.
- Live Fold sync (still the manual `fold.json` snapshot).
- A separate "hide" flag distinct from `locked` (decision 4 reuses `locked`).
- Unrelated refactors beyond what these features touch.

## Build / verify per phase

Each phase ends by building both targets and, where the phase adds pure logic,
running the unit suite:

```
cd apps/mac && xcodegen generate && xcodebuild -project MyOS.xcodeproj \
  -scheme MyOS -configuration Debug -derivedDataPath build build   # mac
cd apps/ios && xcodegen generate && xcodebuild ... -sdk iphonesimulator build  # ios
```

Web (Phase B7) verified with the app's existing web checks and a live chat call.
