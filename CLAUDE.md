# MyOS — Personal Life Operating System

Private, daily-driver "operating system for my life": finance, journal, health, fitness, to-dos, goals, notes, and a mindmap dashboard that visualizes how everything connects. Single-user, privacy-first.

Owner: **Berjil** — personal project. Commit + push as `berjilberjil <berjiljacob@gmail.com>`, GitHub `berjilberjil/MyOS` via the `github-personal` SSH remote (`git@github-personal:berjilberjil/MyOS.git`). **Never** commit as the work/`@skcript.com` identity here.

## Repo structure

```
MyOS/
├── apps/
│   ├── mac/       # Native Swift/SwiftUI Mac app (Xcode project)
│   ├── ios/       # Native Swift/SwiftUI iOS app (Xcode project)
│   └── api/       # Headless SvelteKit backend API (deployed to Netlify) — no web UI
├── supabase/      # Postgres migrations (0001–0014)
├── mcp/           # MCP servers (diet/)
└── scripts/       # Backend LaunchAgent installer
```

## Stack

- **Mac / iOS:** Native Swift + SwiftUI, Xcode, SwiftData
- **Backend API:** SvelteKit 2 (Netlify adapter), Supabase Postgres, Gemini AI
- **Diet MCP:** Bun + stdio transport
- **DB:** Supabase Postgres with RLS

## Run

### Backend API (apps/api)
```bash
cd apps/api
bun install
bun run dev              # http://localhost:5173
```
Or install the LaunchAgent: `scripts/install-backend-agent.sh`

### Mac app (apps/mac)
Open `apps/mac/MyOS.xcodeproj` in Xcode, or use the command-line build.

### iOS app (apps/ios)
Open the Xcode project, or use `xcodebuild`.

### Diet MCP
```bash
cd mcp/diet
bun install
bun run src/index.ts     # stdio transport
```

## Cross-device sync (hosted Supabase)
1. Create a private Supabase cloud project.
2. Apply migrations `supabase/migrations/` (`supabase db push`).
3. Point `apps/api/.env` at the cloud project.
4. Seed the single owner via the admin API; enable MFA. RLS restricts all data to the owner.
Signing in on another device pulls the owner's data down.

## Test / verify
```bash
# Backend API tests
cd apps/api && bun run test

# Mac app tests
cd apps/mac && xcodebuild test
```

## Conventions

- **Deleting is not destroying.** Every user-facing delete captures the object
  into the recycle bin (`Support/Trash.swift`, `AppState+Trash.swift`) and
  releases its R2 objects only when the entry is purged 30 days later. A new
  `delete*` that skips `recycle(...)` is a bug — and one that deletes media in
  the same breath makes restore a lie.
- **Notification ids are namespaced.** `myos.reminder.*` (daily) and
  `myos.event.*` (events) each clear only their own prefix. Never call
  `removeAllPendingNotificationRequests()` — it silently cancels the other
  scheduler's work. iOS caps pending local notifications at 64.
- **Event occurrences are projected, never stored** (`EventRecurrence`). A
  yearly event is one row with a rule, and the day-of-month is always clamped
  from the anchor so a 29 Feb birthday returns on the next leap year.
- **Privacy:** single owner. Public signup disabled. RLS `user_id = auth.uid()` on every table. Private media buckets, signed URLs only. Add RLS + a policy test for every new table.
- **Migrations:** every new table gets its own migration file in `supabase/migrations/`. Always include RLS policies.
- **TDD**, frequent commits, conventional-commit messages.

## Status & roadmap

1. ✅ **Foundation** (Supabase+auth+RLS, data layer, app shell)
2. ✅ **Finance** (accounts, transactions, categories+budgets, recurring, goals, investments)
3. ✅ **Journal** (rich-text + media pipeline, mood/date)
4. ✅ **To-dos + Goals** (priority/due todos, life goals lifecycle)
5. ✅ **Health + Fitness** (daily metrics + workouts)
6. ✅ **Notes** (rich-text notes + pin)
7. ✅ **Mindmap** (SVG life map, module counts + links)
8. ✅ **Native Mac app** (SwiftUI, all modules)
9. ✅ **Native iOS app** (SwiftUI, core modules)
10. ✅ **Fold integration** (banking dashboard via MCP)
11. ✅ **Diet MCP** (meal planning via stdio)
12. ✅ **Recycle bin** (`myos.trash`, 30-day retention, Settings → Recycle bin)
13. ✅ **Recurring events + reminders** (repeat rules, pre-event notifications)

Next work = polish/iterate or extend a module; follow the same brainstorm → spec → plan → build cycle.
