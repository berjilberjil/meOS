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
bunx wrangler secret put MEOS_SECRETS_KEY          # openssl rand -base64 32
bunx wrangler secret put MEOS_PASSWORD_PEPPER      # separate, stable
bunx wrangler secret put MEOS_MFA_RECOVERY_PEPPER  # separate, stable
bunx wrangler secret put MEOS_AUDIT_SALT
# Optional first-run gate (send as setupToken with the first registration):
# bunx wrangler secret put MEOS_SETUP_TOKEN
bunx wrangler secret put GEMINI_API_KEY
bunx wrangler secret put R2_ACCOUNT_ID
bunx wrangler secret put R2_ACCESS_KEY_ID
bunx wrangler secret put R2_SECRET_ACCESS_KEY
bunx wrangler secret put R2_BUCKET
```

`MEOS_SECRETS_KEYS` + `MEOS_SECRETS_KEY_ID` can replace the single
`MEOS_SECRETS_KEY` for rotation; see `SECURITY.md` and `ENCRYPTION.md`.

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
- Session cookie is httpOnly, SameSite=Strict, Secure except localhost. Only a
  SHA-256 hash of the token is stored; legacy rows upgrade on use.
- Passwords are PBKDF2-SHA256 `v3` (peppered with `MEOS_PASSWORD_PEPPER`) or
  `v2`/legacy scrypt; successful sign-in upgrades the hash.
- Optional TOTP MFA with one-time recovery codes. Sensitive actions require a
  5-minute re-auth; export/MFA/secret rotation/AI-key changes ask for the
  password (and MFA) again.
- State is one encrypted document per module. The server stores ciphertext and
  cannot read module contents. Once `meos.crypto` exists, plaintext module
  writes are refused (anti-downgrade); vault-meta replacement needs a fresh
  session/re-auth and deletion is blocked.
- Every row query is scoped by `user_id` — there is no RLS safety net in D1.
- AI/TOTP secrets are AES-256-GCM encrypted with the `MEOS_SECRETS_KEY` ring;
  only masked forms are returned.
- Server-key AI calls and voice characters are capped per user and per account
  per UTC day.
- Security events are metadata-only in `security_events` (salted IP, no
  payloads), exposed at `/api/security/events`.
- Unsafe `/api/*` requests require a trusted Origin; CORS is deny-by-default;
  responses carry CSP/HSTS/frame/nosniff/referrer/COOP/CORP headers.
- Authenticated responses are `Cache-Control: private, no-store`; `/api/anatomy`
  is the only public, cacheable route.

Full model, threat model and evidence: [`../../SECURITY.md`](../../SECURITY.md),
[`../../SECURITY_AUDIT.md`](../../SECURITY_AUDIT.md),
[`../../docs/API_SECURITY.md`](../../docs/API_SECURITY.md).
