# MyOS — To-dos & Goals as inline `/` slash entities — Design Spec

**Date:** 2026-07-12
**Status:** Approved design, pre-implementation
**Goal:** Declutter the app. Remove the To-dos and Goals sub-tabs; create and track both as real entities from inside the Journal/Notes `/` slash menu, embedded as live chips.

## Motivation
The Workspace tab has four sub-tabs (Journal · Notes · To-dos · Goals). To-dos and Goals are low-frequency destinations; capturing them means leaving whatever you're writing. Folding their creation into the editor's existing `/` slash menu removes two tabs and makes capture inline, while keeping the structured data (due dates, priority, buckets, goal lifecycle).

## Locked decisions
1. **Real entities.** `/todo` and `/goal` create real `todos` / `goals` rows (not plain text). They keep due date, priority, overdue/today buckets, goal status + target date.
2. **Live inline chip.** The entity is embedded in the note/journal body as a chip. Checking it in the note marks it done in the DB; it also shows on the Dashboard.
3. **Keep the full pages.** `/todos` and `/goals` remain as full manage-all views, removed from the Workspace tab bar, linked from the Dashboard.
4. **Keep a plain checklist too.** The existing plain-checkbox slash item is renamed **"Checklist"** and kept for throwaway in-note lists, alongside the new smart `/todo`.
5. **Fast capture.** `/todo` uses the current line's text as the title and creates instantly; due date / priority (todo) and status / target date (goal) are set later by tapping the chip.
6. **No schema change.** Chips are references stored inside the existing note/journal TipTap JSON body. `todos` / `goals` tables are unchanged.

## Non-goals (YAGNI for v1)
- Writing `links` rows to surface note↔todo connections in the mindmap (future).
- Offline creation of todos/goals beyond what the current `SupabaseRepository` already does (todos/goals are online-first today; chips inherit that behavior unchanged).
- Rich goal progress inside the chip (milestones, %). Chip shows title + status + target date only.

## Architecture

The Journal and Notes editors are the **same component** (`src/lib/notes/editor/NotesEditor.svelte`), so both get the feature automatically. App behavior is injected into the editor via the existing `editor.storage` seam (already used for `notesPick`).

### Data flow
```
User types "Call plumber" then "/todo" in a note
  → slash item reads the current line text as title
  → editor.storage.planner.createTodo(title) → addTodo() → real row {id,...}
  → replace the line with a todoChip node { id, title, done, due, priority }
Chip render (NodeView):
  → on load, reconcile snapshot from TanStack cache by id (reflects Dashboard-side changes)
  → tap checkbox → editor.storage.planner.toggleTodo(id) → DB + invalidate ['todos'] → update node attr
  → tap chip body → popover: due date + priority (todo) / status + target date (goal)
```

### New units

**`src/lib/notes/editor/blocks.ts` — two new atom nodes**
- `TodoChip` (`name: 'todoChip'`, `atom: true`, `selectable: true`, `draggable: true`)
  - attrs: `todoId` (string), plus a denormalized **snapshot** `title`, `done` (bool), `due` (string|null), `priority` (0–3). Snapshot keeps the note renderable offline and after entity deletion.
  - `addNodeView()` returns an imperative DOM element (matches the codebase's no-Svelte-NodeView style, e.g. the `DragHandle` render): a checkbox, a title label (line-through when done), and a small settings affordance. Reads live state from `editor.storage.planner.getTodo(todoId)` when present, falling back to the snapshot; wires checkbox → `toggleTodo`, body → `openTodoPopover`.
  - `renderHTML` / `parseHTML` on `span[data-todo-chip]` with the snapshot attrs, so the JSON round-trips and non-editor previews still show the title.
- `GoalChip` (`name: 'goalChip'`, same shape) — attrs `goalId`, snapshot `title`, `status` ('active'|'done'|'archived'), `targetDate`. Checkbox toggles active↔done; body popover sets status + target date.

**`src/lib/notes/editor/planner-chip.ts` — pure helpers (unit-tested)**
- `todoChipAttrs(todo): TodoChipAttrs` — entity → snapshot attrs.
- `goalChipAttrs(goal): GoalChipAttrs` — entity → snapshot attrs.
- `reconcileTodoChip(attrs, live: Todo | null): TodoChipAttrs` — prefer live entity; if `live === null` (deleted) mark `removed: true` and keep last snapshot.
- `reconcileGoalChip(...)` — same for goals.
- `chipLabel(attrs)` — display string. Pure, no DOM.

**`src/lib/notes/editor/slash.ts` — three changes**
- Rename existing item `To-do` → `Checklist` (keeps `toggleTaskList()`); update keywords.
- Add `To-do` item: reads current block text via `editor.state`, calls `editor.storage.planner.createTodo(text)`, then `insertContent({ type: 'todoChip', attrs })` replacing the line. Empty line → create "Untitled task" and open the chip popover focused on the title.
- Add `Goal` item: same, `createGoal(text)` → `goalChip`.

**`src/lib/notes/editor/NotesEditor.svelte`**
- Register `TodoChip`, `GoalChip` in `extensions`.
- After construction, set `editor.storage.planner = { createTodo, toggleTodo, updateTodo, getTodo, createGoal, setGoalStatus, updateGoal, getGoal }`, backed by `$lib/planner/*` repos and the injected `QueryClient` (read cache via `qc.getQueryData(['todos'])` / `['goals']`; mutate then `qc.invalidateQueries`). Pass the `QueryClient` in as a prop from the two callers so the editor stays decoupled from routing.
- New prop `queryClient` (or a small `planner` prop object) provided by both the journal and notes edit pages.

**`src/lib/notes/editor/editor.css`** — `.todo-chip` / `.goal-chip` styles (inline pill, checkbox, done = muted + line-through, `removed` = struck + low opacity). Match the 13px compact luma theme; theme-token colors only.

### Nav / routing changes
- `src/routes/(app)/(workspace)/+layout.svelte` — `tabs` becomes `[Journal, Notes]`. Keep the mobile in-content tab row logic.
- `src/lib/nav.ts` — remove the `New to-do` / `New goal` fan-menu items from the `workspace` entry. **Keep** `/todos`, `/goals` in the `match` array so the Workspace tab stays highlighted when viewing those deep pages.
- `/todos` and `/goals` route pages: unchanged (still full manage-all views), just no longer in the tab bar.

### Dashboard (review surface — mostly exists)
`src/routes/(app)/dashboard/+page.svelte` already queries `listTodos()` + `goalsRepo.list()` and renders "To-dos due" and "Goals active". Add:
- A quick-add input on the to-dos widget (title → `addTodo`), and a **"See all →"** link to `/todos`.
- A small active-goals list with **"See all →"** to `/goals`.

## Edge cases
- **Delete the note** → the todo/goal entity is untouched (chip is only a reference).
- **Delete the entity** (from `/todos`) → chip renders the last snapshot, visibly `removed` (struck, muted); never throws. `getTodo` returns `null` → `reconcile*` sets `removed`.
- **Same entity embedded twice** → both chips share the id; toggling reconciles both on next cache read. Acceptable.
- **Empty line `/todo`** → "Untitled task" created; popover opens focused on title.
- **Offline** → `createTodo` behaves exactly as the current `/todos` add path (online-first). If it throws, surface a toast and do not insert a chip.
- **Note preview rendering** (list cards) — if a preview path renders body JSON→HTML without the editor extensions, register `TodoChip`/`GoalChip` there too, or ensure the preview uses text extraction that ignores unknown atoms. Verify during build.

## Testing
- **Unit (Vitest):** `planner-chip.ts` — `todoChipAttrs`, `goalChipAttrs`, `reconcileTodoChip` (live wins; null → removed), `chipLabel`. Pure, no DOM.
- **e2e (Playwright):** open a new note → type "Call plumber" → `/todo` → assert a `todoChip` renders checked-off state toggles, and that the todo appears on `/dashboard`. Second test: `/goal` creates a goal chip.
- `bun run check` = 0 errors (note: pre-existing `PUBLIC_SUPABASE_*` env errors are environmental, unrelated to this change).

## Files touched
| File | Change |
|---|---|
| `src/lib/notes/editor/blocks.ts` | + `TodoChip`, `GoalChip` nodes with NodeViews |
| `src/lib/notes/editor/planner-chip.ts` | + pure snapshot/reconcile/label helpers (new) |
| `src/lib/notes/editor/slash.ts` | rename To-do→Checklist; add smart `/todo`, `/goal` |
| `src/lib/notes/editor/NotesEditor.svelte` | register nodes; inject `editor.storage.planner`; `queryClient` prop |
| `src/lib/notes/editor/editor.css` | chip styles |
| journal + notes edit pages | pass `queryClient`/planner into the editor |
| `src/routes/(app)/(workspace)/+layout.svelte` | tabs → Journal · Notes |
| `src/lib/nav.ts` | drop New to-do / New goal fan items |
| `src/routes/(app)/dashboard/+page.svelte` | quick-add + "See all →" links |
| `tests/unit/planner-chip.test.ts` | new unit tests |
| e2e spec | new slash→entity test |

**No migration.**

## Risks
1. **Interactive NodeView is new here.** Existing custom nodes (`Callout`, `Bookmark`, `FileBlock`) are static `renderHTML`. The chips need `addNodeView()` with event handlers + a way to reach app state (`editor.storage.planner`). Mitigated by the established `editor.storage.notesPick` injection pattern and imperative-DOM precedent (`DragHandle`, slash menu render).
2. **Snapshot vs live drift.** The chip stores a denormalized snapshot for offline/standalone render but reconciles from the query cache on load. If reconciliation is missed, a note could show a stale title. Covered by `reconcile*` unit tests and the e2e Dashboard round-trip.
3. **Preview rendering of unknown nodes** (see edge cases) — verify note/journal list previews don't choke on the new atom nodes.
