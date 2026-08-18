# MyOS — macOS App (Tauri) + Web — Design Spec

**Date:** 2026-06-26
**Status:** Approved for build
**Owner:** Berjil

---

## 1. Purpose

Ship MyOS as a native macOS app (`MyOS.app` / `.dmg`) while keeping the existing web app — both from one SvelteKit codebase. Local-first on each Mac (instant + offline); data syncs across Macs via a private cloud hub so signing in on another Mac restores everything.

## 2. Decisions (locked)

| Decision | Choice | Reason |
|---|---|---|
| Shell | Tauri 2 | Tiny native app (~8MB), macOS WKWebView, real .app/.dmg; reuses the whole SvelteKit app |
| Targets | One codebase → web (static host) + Mac (Tauri bundle) | Single source of truth, no fork |
| Frontend build | Static **SPA** (`adapter-static`, `ssr=false`, SPA fallback) | Tauri bundles static files; same build serves web |
| Auth | Client-side Supabase session + route guard | No Node server in a static/Tauri build |
| Sync backend | Hosted (cloud) Supabase project, RLS-locked to owner | Cross-device sync hub; local Docker stays for dev |
| Local/offline | Existing Dexie cache + sync queue | Offline + instant per device; no data-layer rewrite |
| Not in scope | Local-primary DB rewrite, iOS app, App Store submission | YAGNI now; possible later |

## 3. Architecture

```
ONE SvelteKit codebase (SPA: ssr=false, adapter-static)
  ├─ Web:  static files  → host (Vercel/Netlify/any static)
  └─ Mac:  same files bundled in Tauri 2 → MyOS.app / MyOS.dmg
              macOS WKWebView · native window, menu, dock icon
Data per device:  local cache (IndexedDB/Dexie) — offline + instant
Sync hub:         private Supabase cloud (Postgres + Auth + Storage), RLS owner-only
Flow:  sign in → pull data from Supabase → cache locally → work offline → queue writes → sync on reconnect
```

## 4. The SSR → SPA conversion (the core change)

Current app is SSR with server-side auth. Static/Tauri builds have no server, so:

- **Adapter:** swap `@sveltejs/adapter-node` → `@sveltejs/adapter-static` in `vite.config.ts`, with `fallback: 'index.html'` (SPA).
- **Global SPA flags:** add `src/routes/+layout.ts` with `export const ssr = false;` and `export const prerender = false;`.
- **Client auth guard:** `src/routes/(app)/+layout.svelte` (or `+layout.ts`) checks the Supabase session on the client; no session → `goto('/login')`.
- **Remove server files:** delete `src/hooks.server.ts`, `src/routes/(app)/+layout.server.ts`, `src/routes/login/+page.server.ts`; move their logic to the client login flow (`signInWithPassword` + MFA via the existing browser Supabase client) and the client guard.
- **Security tradeoff (accepted):** session token moves from an httpOnly cookie to Supabase's client storage. Acceptable for a single-owner personal app; documented here.
- **Verify:** web build still loads, login works, route guard redirects, all 7 modules render, existing Playwright e2e still pass (adjusted for client auth if needed).

## 5. Sync backend (hosted Supabase)

- Create a private Supabase **cloud** project; apply migrations `0001`–`0006`.
- Point production env (`PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`) at it; keep `.env.local` → local Docker for dev.
- Public signup stays disabled; single owner seeded via admin API. MFA enabled.
- RLS already enforces owner-only on every table — proven by the RLS test suite.

## 6. Tauri shell

- `src-tauri/`: Rust crate + `tauri.conf.json`.
- `tauri.conf.json`: app name "MyOS", identifier `com.berjil.myos`, window 1200×800 (resizable, min 900×600), bundle icons from the existing PWA icons (generate `.icns`), `frontendDist` → SvelteKit `build/`, `devUrl` → `http://localhost:5177`.
- Minimal plugins (shell/opener only if needed). No custom Rust commands for v1.
- Scripts in `package.json`: `tauri` (CLI), `tauri:dev`, `tauri:build`.

## 7. Build & dev workflow

- **Prereqs (once on the Mac):** Rust (`rustup`) + Xcode command-line tools. A setup check script reports what's missing.
- **Dev (web):** `bun run dev` → http://localhost:5177.
- **Dev (Mac app):** `bun run tauri:dev` → native window loading the dev server.
- **Build (web):** `bun run build` → static `build/` → deploy.
- **Build (Mac app):** `bun run build` then `bun run tauri:build` → `MyOS.app` + `MyOS.dmg` under `src-tauri/target/release/bundle/`.

## 8. Testing

- Existing Vitest unit suite unchanged (pure logic, services) — must stay green.
- Playwright e2e: update auth flow for client-side login if selectors/timing change; all module e2e must pass against the SPA build (preview serves the static build).
- Manual: launch `MyOS.app`, sign in, create data, quit, reopen (data persists), go offline (log entry), reconnect (syncs). Optional second-Mac check: sign in elsewhere → data appears.

## 9. Non-goals (this phase)

- No local-primary database rewrite (offline via existing cache).
- No iOS/iPad app (Tauri mobile deferred).
- No code-signing/notarization/App Store (local `.dmg` is fine for personal use; can add later).
- No change to module features — pure packaging + auth-mode change.
