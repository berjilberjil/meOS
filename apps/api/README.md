# meOS API

Headless SvelteKit API for the native MeOS apps. Runs on **Cloudflare Workers**,
stores encrypted app-state documents in **D1**, media in **R2**, and calls AI
providers through the AI SDK.

There is no web client. The only page is a static landing page.

## Local development

```bash
bun install
bunx wrangler login                  # one-time; the AI binding proxies remotely
cp .env.example .dev.vars
bunx wrangler d1 execute meos --local --file=db/schema.sqlite.sql
bun run dev
```

`bun run dev` uses `adapter-cloudflare`'s platform proxy, so `platform.env.DB`,
`MEDIA` and `AI` match production. The local D1 file lives under `.wrangler/`
and is gitignored.

Without the schema step, login/register/state fail with "no such table". The
schema is idempotent (`create … if not exists`) and safe to re-apply.

## Verify

```bash
bun run check     # svelte-check
bun run test      # vitest
bun run build     # production Worker
```

## Deploy

```bash
bun run build
bunx wrangler deploy
```

Secrets (never in git) are set once per environment:

```bash
bunx wrangler secret put MEOS_SECRETS_KEY     # openssl rand -base64 32
bunx wrangler secret put GEMINI_API_KEY
bunx wrangler secret put R2_ACCOUNT_ID
bunx wrangler secret put R2_ACCESS_KEY_ID
bunx wrangler secret put R2_SECRET_ACCESS_KEY
bunx wrangler secret put R2_BUCKET
```

Apply the schema to the remote database only when it changes:

```bash
bunx wrangler d1 execute meos --remote --file=db/schema.sqlite.sql
```

`db/schema.sqlite.sql` only creates missing objects and indexes; it never drops
tables or columns. `db/schema.sql` is the old Postgres schema and is not used.

## Layout

```
src/
  hooks.server.ts        session → locals.user, scanner junk filter, headers
  lib/server/db.ts       D1 behind a postgres.js-shaped sql template
  lib/server/auth.ts     PBKDF2 passwords, sessions, login throttle, signup gate
  lib/server/stateKeys.ts  the allowlist of syncable module keys
  lib/server/stateVersion.ts  one-row ETag version per user
  lib/server/storage.ts  R2 binding, quota, signed URLs
  lib/server/presign.ts  SigV4 presign on crypto.subtle
  lib/server/ai.ts       per-user routing → server Gemini fallback + metering
  lib/server/aiBudget.ts / voiceBudget.ts  daily spend ceilings
  lib/server/secrets.ts  AES-GCM for user AI keys
  lib/data/              anatomy data
  routes/api/            auth, state, devices, AI, media, macro, voice…
```

## Security model

- Single owner. `POST /api/auth/register` works only while `users` is empty, or
  with `MEOS_ALLOW_SIGNUP=true`.
- Session cookie is httpOnly, SameSite=Lax, Secure except localhost.
- Passwords are PBKDF2-SHA256 (`v2:` format); legacy scrypt hashes still verify
  and are upgraded on the next successful sign-in.
- State is one encrypted document per module. The server stores ciphertext and
  cannot read module contents.
- Every row query is scoped by `user_id` — there is no RLS safety net in D1.
- User AI keys are AES-256-GCM encrypted with `MEOS_SECRETS_KEY`; only the
  masked form is returned to clients.
- Server-key AI calls and voice characters are capped per user and per account
  per UTC day.
- Authenticated responses are `Cache-Control: private, no-store`; `/api/anatomy`
  is the only public, cacheable route.
