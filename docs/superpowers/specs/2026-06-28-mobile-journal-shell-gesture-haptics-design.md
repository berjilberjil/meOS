# Mobile shell: journal-first landing, Workspace quick-create gesture, app-wide haptics

**Date:** 2026-06-28
**Status:** Approved (design)
**Scope:** Mobile-first reshaping of the app shell — change the default landing, restructure the bottom nav around an elevated center Dashboard, add a long-press quick-create gesture on the Workspace tab, and introduce a curated haptics vocabulary across the app.

## Goal

Journaling is the daily-driver activity, so the app should open into it and make starting a new journal (or note) a one-gesture action from anywhere in the bottom nav. Make the shell feel native: elevated center button, fluid gesture animation, and tactile feedback at key moments.

## Non-goals

- No redesign of the journal/notes editors themselves.
- No new quick-create targets beyond Journal and Note (to-dos/goals stay reachable via the Workspace pages).
- No change to desktop behavior beyond what naturally follows (elevated center button shows there too; gesture is harmless but mobile-focused).

## 1. Landing + routing

- App launch lands on the **journal overview** (`/journal`) — which is the existing **Workspace** tab destination.
- Dashboard page moves from `/` (`src/routes/(app)/+page.svelte`) to **`/dashboard`** (`src/routes/(app)/dashboard/+page.svelte`).
- `/` becomes a redirect to `/journal` (so a cold launch never flashes the dashboard).
- Login flow and any `goto('/')` continue to work via the `/` → `/journal` redirect.
- The nav "active" logic updates: Workspace tab matches `/journal` (+ `/notes`, `/todos`, `/goals` as today); Dashboard center matches `/dashboard`.

## 2. Bottom nav layout

```
 Finance   Workspace   ╭──────╮   Fitness   Belongings
                       │ ◉DASH │
                       ╰──────╯   elevated circular button, accent bg,
                                  overlaps the nav's top edge
```

- 5 slots. **Dashboard = raised center button** (~56px circle, `--primary` background, Dashboard icon, subtle shadow), vertically overlapping the top edge of the bar.
- Tap center → navigate `/dashboard` + medium haptic. Active ring/state when on `/dashboard`.
- The other four (Finance, Workspace, Fitness, Belongings) are normal icon+label tabs, unchanged.
- **Life map** leaves the bar and becomes a small icon button in the top bar (`MobileTopBar`), next to the avatar. (Chosen over relocating Belongings because Life map is the least-used daily.)
- Existing desktop auto-hide behavior of the bar is preserved.

## 3. Workspace long-press quick-create gesture

State machine (pure, testable): `idle → primed(Journal) → note(Note) → (fire | cancel) → idle`.

- **Tap** (press < long-press threshold, no significant move): normal navigation to `/journal`. Unchanged.
- **Long-press** (hold ≥ ~350ms): enter quick-create mode.
  - A highlight pill + a floating chip appear above the Workspace button, label **"New Journal"**.
  - Other tabs dim slightly to focus the gesture.
  - Haptic: **medium impact**.
- **Drag right** past ~40px from origin: target → **"New Note"**.
  - The highlight pill slides right under the finger; chip label morphs to "New Note".
  - Haptic: **selection tick** on crossover (once per crossing, debounced so jitter doesn't buzz repeatedly).
- **Drag left back past origin, or drag up/away beyond a cancel radius**: cancel state (chip fades; no haptic).
- **Release**:
  - In `primed(Journal)` → open `/journal/new?date=<today ISO>`; haptic **success**.
  - In `note(Note)` → open `/notes/new`; haptic **success**.
  - In `cancel` → do nothing.
- Motion: spring-eased, ~200–280ms. Respects `prefers-reduced-motion` (no spring; instant show/hide).
- Accessibility/fallback: tap still navigates; the in-page "Today's entry" and "New note" buttons remain, so the gesture is an accelerator, not the only path.

Thresholds (`LONG_PRESS_MS = 350`, `NOTE_DRAG_PX = 40`, `CANCEL_RADIUS_PX = 64`) are constants in the gesture module.

## 4. Haptics system

New module `src/lib/haptics.ts`:

- Thin wrapper over `@tauri-apps/plugin-haptics`. Platform-guarded: only calls the plugin when running natively (reuse the `isTauri()` check pattern from `src/lib/notify.ts`); silent no-op on web/desktop. All calls are fire-and-forget and must never throw.
- Semantic API:
  - `tick()` → `selectionFeedback()`
  - `impact()` → `impactFeedback('medium')`
  - `success()` → `notificationFeedback('success')`
  - `warning()` → `notificationFeedback('warning')`

Curated wiring (the "key moments" vocabulary):

| Interaction | Haptic |
|---|---|
| Bottom-nav tab tap | `tick()` |
| Elevated Dashboard press | `impact()` |
| Primary (`default`-variant) Button press | `impact()` |
| Toggle a to-do done / segmented selects | `tick()` |
| Long-press gesture trigger | `impact()` |
| Drag → Note crossover | `tick()` |
| Gesture fire (open journal/note) | `success()` |
| Create/save success (QuickAdd, journal save, etc.) | `success()` |
| Delete / validation error | `warning()` |

Primary-button coverage is achieved by firing `impact()` inside the shared `Button` component for the `default` variant only (other variants stay silent), so coverage is consistent without instrumenting every call site. Success/warning fire at the relevant mutation `onSuccess`/`onError` / delete sites.

## 5. Dependencies

- Cargo: `tauri-plugin-haptics` (register in `src-tauri/src/lib.rs`, mobile-gated like the existing insets plugin).
- npm: `@tauri-apps/plugin-haptics`.
- Capability: add `haptics:default` (or the specific `allow-*` permissions) to `src-tauri/capabilities/default.json`.

## 6. Testing / verification

- **Unit (Vitest):**
  - Gesture state machine as a pure reducer: `(state, event) → state` covering idle→primed→note→fire/cancel and threshold edges.
  - Haptics wrapper: no-throw and no-op when not native (mock the plugin + platform check).
- `bun run check` → 0 errors.
- Full unit suite green.
- Rebuild + install on iPhone; manually confirm: launch lands on journal, elevated Dashboard works, long-press → journal, long-press+drag-right → note, haptics fire at the curated moments, reduced-motion path is instant.

## 7. Files touched (anticipated)

- `src/lib/nav.ts` — nav items (remove Life map from bar list; mark Dashboard as center; Dashboard href `/dashboard`).
- `src/lib/components/layout/MobileNav.svelte` — 5-slot layout, elevated center button, long-press gesture handling + animation, nav-tap haptics.
- `src/lib/components/layout/MobileTopBar.svelte` — Life map icon button.
- `src/routes/(app)/+page.svelte` → move to `src/routes/(app)/dashboard/+page.svelte`; add `/` redirect (`src/routes/(app)/+page.ts` or equivalent).
- `src/lib/haptics.ts` — new.
- `src/lib/components/ui/button/button.svelte` — primary-variant impact.
- Curated success/warning at: `QuickAdd.svelte`, journal/notes save, to-do toggle, delete actions.
- `src-tauri/Cargo.toml`, `src-tauri/src/lib.rs`, `src-tauri/capabilities/default.json`, `package.json` — haptics plugin.
- Gesture module + its unit test; haptics wrapper test.
