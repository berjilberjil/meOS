# meOS — Personal Life Operating System

Private, daily-driver "operating system for my life": finance (Fold today),
health, fitness, to-dos, goals, notes, events, and a mindmap-ish assistant that
remembers how everything connects. Single owner, privacy-first.

Owner: **Berjil** — personal project. Commit + push as
`berjilberjil <berjiljacob@gmail.com>`, GitHub `berjilberjil/meOS` via the
`github-personal` SSH remote (`git@github-personal:berjilberjil/meOS.git`).
**Never** commit as the work/`@skcript.com` identity here.

## Repo structure

```
meOS/
├── apps/
│   ├── apple/     # MeOS for iPhone + Mac: one SwiftUI codebase (xcodegen)
│   └── api/       # Headless SvelteKit API on Cloudflare Workers — no web UI
├── mcp/
│   ├── diet/      # Meal-plan MCP (stdio, Bun)
│   ├── stuff/     # Purchases / ROI MCP (stdio, Bun)
│   └── meos/      # Central gateway: all modules, stdio + Streamable HTTP (Node)
├── supabase/      # LEGACY pre-Workers schema — not used by the running app
├── scripts/       # LaunchAgent installers + app install / iOS re-sign scripts
├── packaging/     # Homebrew cask for Mac releases
└── docs/          # Architecture notes, finance plan, historical specs
```

## Stack

- **Mac / iOS:** native Swift + SwiftUI (Xcode 26, deployment target 26.0).
  No SwiftData store: modules are Codable documents synced through the API.
- **Backend API:** SvelteKit 2, TypeScript, **Cloudflare Workers** (adapter
  `@sveltejs/adapter-cloudflare`).
- **Database:** **Cloudflare D1 (SQLite)**. Encrypted app-state documents plus
  server-side auth/session/AI-ledger tables. There is no Supabase/Postgres
  runtime and no RLS.
- **Media:** Cloudflare R2, private bucket, presigned GET URLs only.
- **AI:** AI SDK 5 with Gemini / Anthropic / OpenAI. Gemini is the env fallback.
  Voice uses Workers AI (Deepgram Aura).
- **MCP:** Bun + stdio for `diet`/`stuff`; Node 22.18+ with the official SDK
  for the central `meos` gateway (stdio + Streamable HTTP + OAuth 2.1/PKCE,
  per-module scopes, admin dashboard, audit log).

## Run

### Backend API (apps/api)
```bash
cd apps/api
bun install
bunx wrangler login                  # one-time for local D1/R2/AI bindings
cp .env.example .dev.vars            # local only; never commit
bunx wrangler d1 execute meos --local --file=db/schema.sqlite.sql
bun run dev                          # http://localhost:5173
```

`bun run dev` enables the Cloudflare adapter's platform proxy, so D1/R2/AI
bindings come from `wrangler.jsonc`. Without the schema step, login and state
routes fail because `users`/`app_state` do not exist.

Production deploy: `bun run build && bunx wrangler deploy`. Server secrets are
set with `wrangler secret put` — see `apps/api/README.md`.

### iPhone + Mac app (apps/apple)
```bash
cd apps/apple && xcodegen generate   # targets: MeOS (iOS), MeOS-macOS, MeOSWidgets
cd ../.. && ./scripts/install-apps.sh  # build + install both (mac | ios)
```
One set of screens (`Me*.swift`, `Design.swift`) runs on both. The Mac hosts
them in `MeMacShell`; `MacCompat.swift` is the only place iPhone-only API is
translated for macOS. Shared logic lives in `MeOS/Core`, iPhone-only logic
(HealthKit, Photos favorites) in `MeOS/CoreiOS`.

The `.xcodeproj` is generated and gitignored. Re-run `xcodegen generate` after
adding/removing a Swift file, or the build will not see it.

### MCP servers
```bash
cd mcp/diet && bun install && bun run src/index.ts    # stdio
cd mcp/stuff && bun install && bun run src/index.ts
```
`.mcp.json` / `.grok/config.toml` use repo-relative paths; launch the client
from the repository root.

### MeOS MCP gateway (all modules)
```bash
cd mcp/meos
npm install
cp .env.example .env    # MEOS_USERNAME, MEOS_PASSWORD, MEOS_VAULT_PASSPHRASE
npm test                # fake sealed backend + transport tests
npm run start:stdio     # or MEOS_MCP_TRANSPORT=http npm start
```
See `mcp/meos/README.md` for scopes, client configs, the audited capability
matrix, and why there is no transaction-ledger or note-tag tool.

## Sync model

- One encrypted document per module under `app_state`, keyed `meos.<module>`.
- The client hydrates all keys on login, then pushes each changed key with a
  short debounce. `GET /api/state` returns one ETag; a 304 is the normal poll.
- **Adding a module requires three changes:** `StateKey` in
  `apps/apple/MeOS/Core/Models.swift`, `CURRENT_STATE_KEYS` in
  `apps/api/src/lib/server/stateKeys.ts`, and a fixture in
  `stateKeys.test.ts`. The server rejects unknown keys.
- The server never sees plaintext. `meos.crypto` holds the vault metadata; the
  DEK is wrapped on-device with PBKDF2 + AES-GCM.

## Test / verify
```bash
# Backend API
cd apps/api && bun run check && bun run test && bun run build

# Apple: build both targets
cd apps/apple && xcodegen generate \
  && xcodebuild -scheme MeOS-macOS build \
  && xcodebuild -scheme MeOS -sdk iphonesimulator build
```
CI (`.github/workflows/ci.yml`) runs the API type-check, tests and build, plus
both MCP test suites. It does not build Swift. `mac-release.yml` builds an
ad-hoc-signed Mac app on a tag or manual dispatch.

## Conventions

- **The iPhone build expires every 7 days.** This is a free personal team
  (ACDQ327MPR, under the `berjil@skcript.com` Apple ID), so the embedded
  provisioning profile lasts a week and the app stops launching when it lapses.
  `scripts/refresh-ios.sh` runs nightly at 22:00 via the
  `com.berjil.meos.iosrefresh` LaunchAgent to mint a new profile and reinstall.
  Reinstalling the same build does NOT reset the clock — the date lives in the
  profile, so the script deletes the cached profile and the built `.app` to
  force a real re-sign, then reads the expiry back out of the bundle to prove
  it moved. Any change to the build must keep that proof step.
- **Deleting is not destroying.** Every user-facing delete captures the object
  into the recycle bin (`Core/Trash.swift`, `AppState+Trash.swift`) and releases
  its R2 objects only when the entry is purged 30 days later. A new `delete*`
  that skips `recycle(...)` is a bug — and one that deletes media in the same
  breath makes restore a lie.
- **Notification ids are namespaced.** `meos.reminder.*` (daily) and
  `meos.event.*` (events) each clear only their own prefix. Never call
  `removeAllPendingNotificationRequests()` — it silently cancels the other
  scheduler's work. iOS caps pending local notifications at 64.
- **Event occurrences are projected, never stored** (`EventRecurrence`). A
  yearly event is one row with a rule, and the day-of-month is always clamped
  from the anchor so a 29 Feb birthday returns on the next leap year.
- **Privacy:** single owner. Registration is closed after the first account
  (`MEOS_ALLOW_SIGNUP=true` is the deliberate override). Media buckets are
  private; only signed URLs leave the server. Every authenticated state row is
  scoped by `user_id`; there is no RLS to fall back on, so every query must
  include that predicate.
- **Secrets:** never commit them. Server secrets live in Wrangler; user AI
  keys and TOTP seeds are AES-256-GCM encrypted with the `MEOS_SECRETS_KEY`
  ring. Login-password pepper and MFA recovery pepper are separate stable values.
- **Security:** read `SECURITY.md` before changing auth, state, media or MCP.
  Sessions are hash-only; unsafe API requests need a trusted Origin; once
  `meos.crypto` exists the server refuses plaintext module values. The MCP
  gateway is local and holds the vault DEK by design; never move decryption into
  the Worker.
- **TDD**, frequent commits, conventional-commit messages.

## Status & roadmap

1. ✅ Foundation (Workers + D1 + custom auth + vault)
2. ✅ Health + Fitness + Nutrition + Gym
3. ✅ To-dos + Goals, Notes, Events + recurring reminders
4. ✅ Assistant (Catherine) + memory + voice
5. ✅ Scan, Stuff, Macro, Gallery, Devices, Recycle bin
6. ✅ Native Mac + iOS apps from one SwiftUI codebase
7. ✅ Fold integration (read-only banking dashboard)
8. ✅ Six-Pack Challenge + Home Screen widget
9. ✅ Central MeOS MCP gateway (`mcp/meos`: scoped auth, vault, 97 tools,
   resources, prompts, stdio + Streamable HTTP)
10. ⏳ **Personal Finance expansion** — historical ledger, imports,
   reconciliation, multi-year reports. See `docs/finance-foundation.md`.
11. Legacy to retire when safe: `supabase/`, `db/schema.sql` (Postgres),
    `scripts/install-backend-agent.sh` (pre-Workers local server).

Next work = polish/iterate or extend a module; follow the same brainstorm →
spec → plan → build cycle.
