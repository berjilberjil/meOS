# Database security

MeOS uses **Cloudflare D1 (SQLite)**. There is no Postgres/Supabase at runtime and no RLS. This document
records the actual controls and the compensating measures.

## 1. Access path

- The only client is the Worker, through the `DB` binding from `wrangler.jsonc`.
- There is no public database endpoint, no connection string in the app, and no service-role key in a
  browser or in MCP.
- The MCP gateway talks to the Worker over HTTPS with a normal user session; it never sees D1.
- `supabase/` is legacy and not deployed.

## 2. Tables

| Table | Owner column | Contents | Notes |
|---|---|---|---|
| `users` | `id` | username, password hash | single owner; signup closed after first |
| `sessions` | `user_id` | token hash, public id, expiry, timestamps, UA, IP hash, reauth | raw cookie never stored |
| `app_state` | `user_id` | module JSON (ciphertext for E2E modules) | PK `(user_id, key)`; allowlisted keys |
| `ai_credentials` | `user_id` | provider, label, encrypted secret, masked, models | AES-GCM with `MEOS_SECRETS_KEY` |
| `voice_budget` | `user_id` | chars/day | spend cap |
| `ai_budget` | `user_id` | calls/day | server-key spend cap |
| `login_attempts` | none (scope string) | `u:<username>` / `i:<ip>` failures | global by design |
| `state_version` | `user_id` | monotonic ETag version | one row per user |
| `devices` | `user_id` | name, platform, timestamps | pre-unlock metadata |
| `macro_day` | `user_id` | cached macro snapshot | runtime-pruned |
| `security_events` | `user_id` (nullable) | audit metadata | 180-day prune |
| `user_mfa` | `user_id` | encrypted TOTP secret | one row |
| `mfa_recovery_codes` | `user_id` | hashed one-time codes | burned on use |

## 3. Ownership rules

Every user-owned query includes `user_id = <session user>`:

- reads: `app_state`, `ai_credentials`, `devices`, `sessions`, `security_events`, `macro_day`, MFA.
- writes: inserts set the session `user_id`; updates/deletes include `user_id` in the `where`.
- R2 keys are `<kind>/<user id>/<id>`; listing and signing always use the session user's prefix.
- AI key routes check `id` **and** `user_id`; a wrong id is 404.
- State key deletion is scoped; there is no cross-user delete.

There is no endpoint that accepts a `user_id`, `account`, role or table name from the client.

## 4. SQL injection

- All application queries use the tagged template `sql` in `lib/server/db.ts`, which binds values and
  joins literals on `?`. Values are never concatenated into SQL text.
- The one raw DDL helper (`execLiteral`) is used only for `ALTER TABLE sessions ADD COLUMN <fixed name>
  <fixed type>` from a hardcoded allowlist. It never receives a request value.
- Dynamic identifiers do not exist for reads/writes. State keys are values, not identifiers.
- `sql.json()` serializes JSON; it does not execute it.

## 5. Migrations

- `db/schema.sqlite.sql` is the fresh-database shape.
- Runtime ensures additive structures (`sessions` columns, audit, MFA, devices) with `create table if not
  exists` / `alter table add column` guarded by `pragma table_info`.
- No destructive migration is executed by the app. Column drops/rewrites require a reviewed manual
  migration and a backup.
- Deploy order: backup → apply additive DDL → deploy code → verify. The code tolerates missing new columns
  during the transition (session upgrade path).

## 6. Least privilege / service role

- D1 bindings are account-scoped; the Worker can read/write the whole database by design. There is no
  per-table DB role in D1. The compensating control is the single Worker code path and the scoping review.
- Cloudflare account access is the real superuser. Use a dedicated account, hardware 2FA, scoped API
  tokens, and no shared login. Do not put a Cloudflare API token in the Worker.
- The MCP gateway has no D1 credential.

## 7. Backups and recovery

- D1 Time Travel (30 days) for point-in-time recovery.
- Offsite encrypted exports via `scripts/backup-d1.sh` (age).
- Backups contain ciphertext + metadata + password/session hashes. Treat them as sensitive.
- Restore into a local D1 first; verify module count, `meos.crypto`, and one decrypt; then promote.
- A backup does not contain R2 objects; copy the bucket separately if needed.

See [`BACKUP.md`](BACKUP.md).

## 8. Verification

- `apps/api/src/lib/server/stateKeys.test.ts` — allowlist + envelope/meta validation.
- `mcp/meos/tests/auth.test.ts` — cross-account reads return `not_found`.
- `mcp/meos/tests/security.test.ts` — scope and audit isolation.
- Code review checklist for any new query: does it have `user_id`? is the value bound? is the route
  authenticated? is the response free of other users' data?
- Manual: `wrangler d1 execute meos --remote --command "select count(*) from app_state where user_id = ..."`,
  and inspect one `value` to confirm it is `{v,ct}` for a sealed module.

## 9. Residual

- No RLS: a future query that forgets `user_id` is a cross-user bug. This is why the app stays single-owner
  and why every query is reviewed. A move to Postgres/Supabase would allow RLS as a second layer.
- D1 admins can read metadata and delete rows; E2E content stays ciphertext.
- SQLite has no row-level audit triggers here; the app writes audit rows explicitly.
