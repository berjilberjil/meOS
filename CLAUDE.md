# MyOS — Personal Life Operating System

Private, daily-driver "operating system for my life": finance, journal, health, fitness, to-dos, goals, notes, and a mindmap dashboard that visualizes how everything connects. Single-user, privacy-first.

Owner: **Berjil** — personal project. Commit + push as `berjilberjil <berjiljacob@gmail.com>`, GitHub `berjilberjil/MyOS` via the `github-personal` SSH remote (`git@github-personal:berjilberjil/MyOS.git`). **Never** commit as the work/`@skcript.com` identity here.

## Reference (read-only)
`/Users/berjilskcript/Documents/monorepo` ("Knol", SvelteKit) is a **read-only reference** for theme/color/animation tokens and the content-studio interaction flow. **Never modify it.** Design tokens were ported into `src/routes/layout.css`.

## Stack
SvelteKit 2 + Svelte 5 (runes) · Tailwind v4 (CSS-first, `@theme inline` in `src/routes/layout.css`, no `tailwind.config.js`) · shadcn-svelte "luma" + Bits UI · TipTap · TanStack Svelte Query · Supabase (Postgres + Auth + Storage) · Dexie (offline) · `@vite-pwa/sveltekit`. Runtime: **Bun**. Dev port **5177**.

## Run
```bash
bunx supabase start      # local backend (Docker)
bun run dev              # http://localhost:5177
```
Local dev owner (placeholder — change before real use): `owner@myos.local` / `ChangeMe!myos1`.

## Desktop (macOS) + web
One SvelteKit codebase, built as a static SPA (`adapter-static`, `ssr=false`); auth is client-side via Supabase.
- Web dev: `bun run dev` (http://localhost:5177)
- Mac app dev: `bun run tauri:dev` (native window; needs Rust + Xcode CLT — both installed)
- Web build: `bun run build` → static `build/` (deploy to any static host)
- Mac app build: `bun run tauri:build` → `src-tauri/target/release/bundle/` (`MyOS.app` + `MyOS_*.dmg`)
- Tauri config: `src-tauri/tauri.conf.json` (window, icons, `com.berjil.myos`). Build artifacts in `src-tauri/target` (gitignored).

### Cross-device sync (hosted Supabase)
Local-first per device (Dexie cache + sync queue); a hosted Supabase project is the sync hub.
1. Create a private Supabase cloud project.
2. Apply migrations `0001`–`0006` (`supabase db push` to the linked project).
3. Point `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_ANON_KEY` at the cloud project in the build env.
4. Seed the single owner via the admin API; enable MFA. RLS already restricts all data to the owner.
Signing in on another Mac pulls the owner's data down and caches it locally.

## Test / verify
```bash
bun run test -- --run    # Vitest unit suite
bun run check            # svelte-check (must be 0 errors)
bunx playwright test     # e2e (builds + previews on :4173)
# RLS integration tests (needs local stack). Signup is disabled, so the tests
# create users via the admin/service_role API — both keys required:
export SUPABASE_ANON_KEY="$(bunx supabase status -o env | grep '^ANON_KEY=' | cut -d'\"' -f2)"
export SUPABASE_SERVICE_ROLE_KEY="$(bunx supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d'\"' -f2)"
bun run test -- --run tests/unit/rls.test.ts tests/unit/finance-rls.test.ts
```

## Conventions
- **Money is integer paise** everywhere (`src/lib/money.ts`). Never store float money.
- **Privacy:** single owner. Public signup disabled. RLS `user_id = auth.uid()` on every table. Private media buckets, signed URLs only. Add RLS + a policy test for every new table.
- **Data access** via `src/lib/data/repository.ts` (`Repository<T>` / `SupabaseRepository`) and `storage-service.ts`; offline writes go through `sync-queue.ts`.
- **Components:** shadcn-svelte luma in `src/lib/components/ui` (`import * as Card from '$lib/components/ui/card'`). 13px-base compact UI. Three themes: light / dark / Tokyo Night (`tui`).
- **TDD**, frequent commits, conventional-commit messages.

## Status & roadmap
Specs + plans in `docs/superpowers/`. Build order (each module = own brainstorm → spec → plan → build):

1. ✅ **Phase 0 — Foundation** (scaffold, themes, primitives, app shell, Supabase+auth+RLS, data layer, offline sync, PWA)
2. ✅ **Phase 1 — Finance** (accounts, transactions, 3-second quick-add, categories+budgets, recurring/subscriptions catch-up, savings goals, investments/SIPs, dashboard. `src/lib/finance/`.)
3. ✅ **Phase 2 — Journal** (TipTap rich-text + media pipeline, mood/date, list/edit. `src/lib/journal/`.)
4. ✅ **Phase 3 — To-dos + Goals** (priority/due todos, life goals lifecycle. `src/lib/planner/`.)
5. ✅ **Phase 4 — Health + Fitness** (daily metrics + workouts, integer units g/m/min. `src/lib/health/`.)
6. ✅ **Phase 5 — Notes** (rich-text notes + pin, shared TipTap editor. `src/lib/notes/`.)
7. ✅ **Phase 6 — Mindmap life-dashboard** (SVG life map over module counts + `links`. `src/lib/mindmap/`.)

**All 7 phases complete.** Migrations `0001`–`0006`. Every module: own schema+RLS, pure-logic units tested, e2e per module. Next work = polish/iterate or extend a module; follow the same brainstorm → spec → plan → build cycle. Mindmap currently shows module branches; richer entity links accumulate via the `links` table as modules write to it.
