# Migration: Supabase + Netlify → Cloudflare (Workers + D1 + R2)

**Decided 2026-08-20.** Goal: one vendor. Today we run three — Supabase (4 Postgres
tables), Netlify (the SvelteKit API), Cloudflare R2 (media). End state: Cloudflare only.

## Why now

Supabase egress hit **62.7 GB / 5 GB (1,254%)**; grace period ends **19 Sep 2026**,
after which requests 402. Root cause is not the platform — see "Forced order" below.

## What we actually use Supabase for

Nothing Supabase-specific. No Auth, Storage, Realtime, RLS or Edge Functions.
Just 4 tables (`users`, `sessions`, `app_state`, `ai_credentials`, 46 lines of DDL)
reached over plain `postgres.js`. Every query is single-table, no joins, no `jsonb`
operators. `app_state` *is* the product: `(user_id, key, value jsonb, updated_at)`.

## Forced order (do not reorder)

Two Cloudflare limits dictate the sequence:

| Limit | Value | Us today |
|---|---|---|
| D1 max row/value | 2,000,000 bytes | `myos.events` = **2.09 MB** ❌ |
| Workers req/day (free) | 100,000 | poll = **86,400** ⚠️ |

### 1. Event media → R2  *(unblocks D1)*
`EventMedia.data` is inline base64 (`Models.swift:600`) — images *and* mp4 video.
That is 2.04 MB of a 2.27 MB payload (87.8%). Progress photos already moved to R2;
Events never did. Move them the same way → `myos.events` drops to a few KB of keys.
Also kills 88% of egress on its own.

### 2. ETag / 304 + poll backoff  *(unblocks Workers request cap)*
`AppState.startLiveSync` polls every 2s (`AppState.swift:508`) and
`fetchStateRaw` re-downloads the whole state every time — no `If-None-Match`, and the
server (`routes/api/state/+server.ts`) sends no `ETag`. **`app_state.updated_at`
already exists** — `select max(updated_at) where user_id = $1` is the ETag.
Add 304 handling + back the poll off to 15–30s and pause when unfocused.

### 3. Port to Cloudflare  *(kills Supabase AND Netlify)*
Smaller than expected — **it is an adapter swap, not a rewrite**:
- `@sveltejs/adapter-netlify` → `@sveltejs/adapter-cloudflare` (svelte.config.js,
  the only Netlify coupling; there is no netlify.toml)
- `src/lib/server/db.ts`: `postgres.js` → D1 binding; port ~16 trivial queries
- Schema → SQLite: `serial`→INTEGER PK AUTOINCREMENT, `timestamptz`→TEXT ISO,
  `jsonb`→TEXT, `now()`→CURRENT_TIMESTAMP
- Data: dump 4 tables → import to D1 (35 MB, trivial)
- 22 routes carry over untouched

**Bonus:** chat was downgraded from streaming to buffered because Netlify's function
gateway 502'd (`routes/api/chat/+server.ts:38`). Workers streams natively — that
workaround can be reverted.

## Cutover is reversible

`APIClient.baseURL` reads UserDefaults `myos.baseURL` before falling back to
`https://myos-berjil.netlify.app` (`APIClient.swift:18`). So point one device at the
Workers URL with `defaults write`, verify, and roll back instantly. No rebuild.

## Known gotchas

- **scrypt vs Workers free CPU.** `lib/server/auth.ts` uses `scryptSync` (~50–100ms);
  Workers free allows 10ms CPU/invocation. Logins are rare and Paid ($5/mo) gives 30s
  — but expect free-tier login to trip. `node:crypto` is otherwise fully supported
  (only argon2/DSA-DH/ed448/x448/FIPS are excluded), and `nodejs_compat` is default
  for compat dates ≥ 2026-08-04.
- D1 free database cap is 500 MB (we're at 35 MB).
- Workers/R2 have **no egress charges** — the right shape for a blob-sync app.

## Verify

Steps 1–2 land on the current stack and should drop egress from 62.7 GB to <1 GB
before any migration, so we are not racing the 19 Sep deadline during cutover.
