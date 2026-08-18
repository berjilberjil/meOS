# MyOS macOS (Tauri) + Web — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MyOS as a native macOS app (`MyOS.app`/`.dmg`) via Tauri 2 while keeping the web app — one SvelteKit codebase, built as a static SPA with client-side auth.

**Architecture:** Convert the SvelteKit app from SSR (adapter-node, server auth) to a static SPA (adapter-static, `ssr=false`, client auth guard). Tauri 2 bundles the static `build/` output into a native macOS app using the system WebView. Data stays local-first via the existing Dexie cache + sync queue; cross-device sync uses a hosted Supabase project.

**Tech Stack:** SvelteKit 2, Svelte 5, Bun, `@sveltejs/adapter-static`, Tauri 2 (`@tauri-apps/cli`, Rust), Supabase, Vitest, Playwright.

## Global Constraints

- **Runtime:** Bun. Dev port **5177** (`strictPort`).
- **One codebase, two targets:** same build serves web (static host) and Mac (Tauri bundle). No forked code.
- **SPA:** `export const ssr = false` globally; `adapter-static` with `fallback: 'index.html'`. No `.server.ts` files, no `hooks.server.ts` (no Node server at runtime).
- **Auth:** client-side Supabase session (`supabaseBrowser()`), guard in universal `load`. Login flow already client-side — keep it.
- **Privacy:** single owner, RLS owner-only (unchanged). Public signup disabled.
- **`bun run check` must report 0 errors before each commit.** Existing Vitest + Playwright suites must stay green.
- **Toolchain (already present on this Mac):** Rust/cargo (`~/.cargo/bin`), Xcode (`/Applications/Xcode.app`). No install step needed.
- **Commits:** one per task, conventional messages. Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

```
vite.config.ts                       # MODIFY: adapter-node -> adapter-static (SPA fallback)
package.json                         # MODIFY: deps + tauri scripts
src/
  routes/
    +layout.ts                       # CREATE: ssr=false, prerender=false (whole app = SPA)
    (app)/+layout.ts                 # CREATE: client auth guard (no session -> /login)
    (app)/+layout.server.ts          # DELETE (server guard)
    login/+page.ts                   # CREATE: redirect to / if already signed in
    login/+page.server.ts            # DELETE
  hooks.server.ts                    # DELETE (no server runtime)
  lib/server/supabase.ts             # DELETE (server-only client, now unused)
  app.d.ts                           # MODIFY: drop App.Locals (no server locals)
src-tauri/                           # CREATE (via tauri init): Rust crate + config
  tauri.conf.json                    # Tauri 2 config: window, bundle, frontendDist, devUrl
  Cargo.toml, src/main.rs, build.rs, icons/
CLAUDE.md                            # MODIFY: macOS build/run + hosted-Supabase note
```

**Stages:** 1 SPA conversion (keeps web working) → 2 Tauri shell (Mac app) → 3 docs + sync pointer.

---

## Stage 1 — SSR → SPA conversion

### Task 1: Switch to adapter-static (SPA)

**Files:**
- Modify: `package.json` (swap adapter dep)
- Modify: `vite.config.ts`
- Create: `src/routes/+layout.ts`

**Interfaces:**
- Produces: a static SPA build in `build/` with `index.html` fallback; global `ssr=false`, `prerender=false`.

- [ ] **Step 1: Install adapter-static, remove adapter-node**

Run:
```bash
bun add -d @sveltejs/adapter-static
bun remove @sveltejs/adapter-node
```
Expected: `@sveltejs/adapter-static` in devDependencies.

- [ ] **Step 2: Point the SvelteKit plugin at adapter-static** — in `vite.config.ts`, change the import and the `adapter()` call:

Replace:
```ts
import adapter from '@sveltejs/adapter-node';
```
with:
```ts
import adapter from '@sveltejs/adapter-static';
```
and replace `adapter: adapter()` with:
```ts
adapter: adapter({ fallback: 'index.html' })
```

- [ ] **Step 3: Make the whole app a client-rendered SPA**

Create `src/routes/+layout.ts`:
```ts
// MyOS ships as a static SPA (web host + Tauri bundle): no SSR, no prerender.
export const ssr = false;
export const prerender = false;
```

- [ ] **Step 4: Build and confirm static SPA output**

Run: `bun run build`
Expected: completes with `@sveltejs/adapter-static`; `build/index.html` exists and `build/` contains hashed `_app/` assets. Verify:
```bash
test -f build/index.html && echo "SPA fallback OK"
```

- [ ] **Step 5: Commit**

```bash
git add package.json bun.lock vite.config.ts src/routes/+layout.ts
git commit -m "build: convert to static SPA (adapter-static, ssr off)"
```

### Task 2: Client-side auth guard; remove server auth

**Files:**
- Create: `src/routes/(app)/+layout.ts`
- Create: `src/routes/login/+page.ts`
- Delete: `src/routes/(app)/+layout.server.ts`, `src/routes/login/+page.server.ts`, `src/hooks.server.ts`, `src/lib/server/supabase.ts`
- Modify: `src/app.d.ts`

**Interfaces:**
- Consumes: `supabaseBrowser()` from `$lib/supabase/client`.
- Produces: client guard that redirects unauthenticated users to `/login`, and bounces authenticated users away from `/login`. Returns `{ user }` from the `(app)` layout load.

- [ ] **Step 1: Add the client guard for the authed group**

Create `src/routes/(app)/+layout.ts`:
```ts
import { redirect } from '@sveltejs/kit';
import { supabaseBrowser } from '$lib/supabase/client';
import type { LayoutLoad } from './$types';

// Runs in the browser (ssr=false). No valid session -> bounce to login.
export const load: LayoutLoad = async () => {
	const {
		data: { session }
	} = await supabaseBrowser().auth.getSession();
	if (!session) throw redirect(302, '/login');
	return { user: session.user };
};
```

- [ ] **Step 2: Add the login redirect-if-signed-in**

Create `src/routes/login/+page.ts`:
```ts
import { redirect } from '@sveltejs/kit';
import { supabaseBrowser } from '$lib/supabase/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
	const {
		data: { session }
	} = await supabaseBrowser().auth.getSession();
	if (session) throw redirect(302, '/');
	return {};
};
```

- [ ] **Step 3: Delete the server-side auth files**

Run:
```bash
git rm src/hooks.server.ts "src/routes/(app)/+layout.server.ts" src/routes/login/+page.server.ts src/lib/server/supabase.ts
```
Expected: four files removed.

- [ ] **Step 4: Drop server locals from app types** — replace `src/app.d.ts` with:
```ts
// See https://svelte.dev/docs/kit/types#app.d.ts
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}  // no server runtime — SPA + client auth
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
```

- [ ] **Step 5: Type-check + build**

Run: `bun run check`
Expected: 0 errors (no remaining references to `locals`, `hooks.server`, or `$lib/server`).

Run: `bun run build`
Expected: builds clean as SPA.

- [ ] **Step 6: Run the full e2e suite against the SPA build**

Run: `bunx playwright test`
Expected: all pass — `auth.spec` (unauthenticated `/` → client-redirects to `/login`), `shell.spec` (login → dashboard), and every module spec. If a test races the client redirect, add `await page.waitForURL(/\/login/)` before asserting; do not weaken assertions.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(auth): client-side route guard; drop SSR/server auth for SPA"
```

---

## Stage 2 — Tauri macOS shell

### Task 3: Scaffold + configure Tauri 2, build the Mac app

**Files:**
- Modify: `package.json` (Tauri CLI dep + scripts)
- Create: `src-tauri/` (via `tauri init`): `tauri.conf.json`, `Cargo.toml`, `src/main.rs`, `build.rs`, `icons/`

**Interfaces:**
- Consumes: the static `build/` output from Stage 1.
- Produces: `bun run tauri:dev` (native dev window) and `bun run tauri:build` (`MyOS.app` + `MyOS.dmg`).

- [ ] **Step 1: Add the Tauri CLI**

Run: `bun add -d @tauri-apps/cli`
Expected: `@tauri-apps/cli` in devDependencies.

- [ ] **Step 2: Scaffold the Tauri crate (non-interactive)**

Run:
```bash
bunx tauri init --ci \
  --app-name "MyOS" \
  --window-title "MyOS" \
  --frontend-dist ../build \
  --dev-url http://localhost:5177 \
  --before-dev-command "bun run dev" \
  --before-build-command "bun run build"
```
Expected: `src-tauri/` created with `tauri.conf.json`, `Cargo.toml`, `src/main.rs`, `build.rs`.

- [ ] **Step 3: Set identifier, window sizing, bundle targets, and relax CSP for Supabase** — edit `src-tauri/tauri.conf.json` so these keys are set (merge into the generated file):

```json
{
	"productName": "MyOS",
	"identifier": "com.berjil.myos",
	"app": {
		"windows": [
			{ "title": "MyOS", "width": 1200, "height": 800, "minWidth": 900, "minHeight": 600, "resizable": true }
		],
		"security": { "csp": null }
	},
	"bundle": {
		"active": true,
		"targets": ["app", "dmg"],
		"icon": ["icons/32x32.png", "icons/128x128.png", "icons/128x128@2x.png", "icons/icon.icns", "icons/icon.png"]
	}
}
```
(`security.csp: null` lets the WebView reach `https://*.supabase.co`. Keep `build.frontendDist` = `../build` and `build.devUrl` = `http://localhost:5177` from Step 2.)

- [ ] **Step 4: Generate app icons from the existing PWA icon**

Run: `bunx tauri icon static/icon-512.png`
Expected: populates `src-tauri/icons/` with `.icns`, `.ico`, and PNG sizes.

- [ ] **Step 5: Add npm scripts** — in `package.json` `"scripts"`, add:
```json
		"tauri": "tauri",
		"tauri:dev": "tauri dev",
		"tauri:build": "tauri build"
```

- [ ] **Step 6: Dev smoke — native window loads the app**

Run: `bun run tauri:dev`
Expected: first run compiles the Rust shell (slow, minutes), then a native macOS window opens showing MyOS at the login screen. Sign in works. Close the window to stop. (If it hangs on first compile, that's normal cold Rust build time.)

- [ ] **Step 7: Production build — produce the .app and .dmg**

Run: `bun run tauri:build`
Expected: builds the SPA then the Rust release, emitting:
- `src-tauri/target/release/bundle/macos/MyOS.app`
- `src-tauri/target/release/bundle/dmg/MyOS_0.1.0_aarch64.dmg` (name varies by version/arch)

Verify:
```bash
ls -d src-tauri/target/release/bundle/macos/MyOS.app && echo "APP BUILT"
```

- [ ] **Step 8: Ignore Tauri build artifacts** — append to `.gitignore`:
```
/src-tauri/target
```

- [ ] **Step 9: Commit**

```bash
git add package.json bun.lock src-tauri .gitignore
git commit -m "feat(tauri): macOS app shell — window, icons, dmg build"
```

---

## Stage 3 — Docs + cross-device sync pointer

### Task 4: Document build/run + hosted-Supabase sync

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Produces: clear run/build instructions for web + Mac, and the steps to point at a hosted Supabase project for cross-Mac sync.

- [ ] **Step 1: Update the Run section** — in `CLAUDE.md`, add under the run/build docs:
```markdown
## Desktop (macOS) + web
- Web dev: `bun run dev` (http://localhost:5177)
- Mac app dev: `bun run tauri:dev` (native window)
- Web build: `bun run build` → static `build/` (deploy to any static host)
- Mac app build: `bun run tauri:build` → `src-tauri/target/release/bundle/` (`MyOS.app` + `.dmg`)
- App is a static SPA (`adapter-static`, `ssr=false`); auth is client-side via Supabase.

### Cross-device sync (hosted Supabase)
Local-first per device (Dexie cache + sync queue); a hosted Supabase project is the sync hub.
1. Create a private Supabase cloud project.
2. Apply migrations `0001`–`0006` (or `supabase db push` to the linked project).
3. Set `PUBLIC_SUPABASE_URL` / `PUBLIC_SUPABASE_ANON_KEY` to the cloud project in the build env.
4. Seed the single owner via the admin API; enable MFA. RLS already restricts all data to the owner.
Signing in on another Mac pulls the owner's data down and caches it locally.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: macOS + web build/run + hosted Supabase sync"
```

---

## Final verification

- [ ] `bun run check` → 0 errors.
- [ ] `bun run test -- --run` → unit suite green (unchanged).
- [ ] `bunx playwright test` → all e2e green against the SPA build.
- [ ] `bun run build` → static `build/` with `index.html` fallback.
- [ ] `bun run tauri:build` → `MyOS.app` opens, login works, data persists across relaunch.
- [ ] Manual offline check: log an entry offline in the app, reconnect, confirm it syncs.
