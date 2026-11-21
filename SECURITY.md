# MeOS security

MeOS is a **single-owner, privacy-first personal operating system**: a native iPhone/macOS app, a
Cloudflare Workers API backed by D1 and R2, and a local MCP gateway for AI clients. This document
describes the security architecture, the operational rules, and how to report a problem.

The honest summary:

- Designated personal data is **end-to-end encrypted on the client**. The Worker stores ciphertext and
  cannot decrypt it.
- AI provider keys and TOTP secrets are encrypted **server-side** with a master key. That is not
  end-to-end encryption and is labelled as such.
- The MCP gateway runs on the owner's machine. ChatGPT reaches it through an HTTPS tunnel. The gateway,
  not the Worker, decrypts and enforces per-module scopes.
- The system is hardened and tested, but it is not magic. The threat model, residual risks and evidence
  are in [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) and [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md).

---

## 1. Architecture and trust boundaries

```
┌──────────────────────────┐        TLS 1.3        ┌──────────────────────────────┐
│ iPhone / Mac (SwiftUI)   │ ────────────────────▶ │ Cloudflare Worker (apps/api) │
│  • login password        │  httpOnly session     │  • auth, sessions, MFA       │
│  • vault passphrase      │  cookie               │  • ownership checks          │
│  • DEK in Keychain       │                       │  • audit metadata            │
│  • AES-GCM sealing       │ ◀──────────────────── │  • ciphertext only           │
└──────────┬───────────────┘                       └──────────────┬───────────────┘
           │                                                       │
           │ local MCP (stdio)                                     │ D1 (ciphertext +
           ▼                                                       │ metadata) + R2
┌──────────────────────────┐        HTTPS tunnel       ┌──────────▼───────────────┐
│ mcp/meos gateway         │ ◀─────────────────────── │ ChatGPT / Claude / Cursor │
│  • vault DEK in memory   │   OAuth 2.1 + PKCE        │  (third-party processor)  │
│  • per-module scopes     │   Bearer access token     └──────────────────────────┘
│  • consent + /admin      │
│  • audit + idempotency   │
└──────────────────────────┘
```

Trust boundaries:

| Boundary | What crosses it | Protection |
|---|---|---|
| App ↔ Worker | session cookie, ciphertext, public vault metadata, media ciphertext | TLS, HttpOnly/SameSite=Strict cookie, origin checks, rate limits, audit |
| App ↔ Keychain | DEK | `ThisDeviceOnly`, device unlock |
| Worker ↔ D1 | ciphertext, hashes, metadata | D1 access is via the Worker binding only; no public DB endpoint |
| Worker ↔ R2 | encrypted media | private bucket, signed GET only, 10-minute TTL |
| Worker ↔ AI providers | prompt + whatever the *app* includes | user keys encrypted at rest; server AI keys are metered; provider sees the prompt |
| Gateway ↔ MeOS API | login session, ciphertext | HTTPS, server-side credentials, no service-role key |
| Gateway ↔ AI client | decrypted tool results | OAuth scopes, consent, rate limits, audit, revocation |
| Owner ↔ gateway | vault passphrase, admin password | local process/env, 0600 files, loopback bind |

---

## 2. What is end-to-end encrypted (and what is not)

### E2E encrypted (client holds the key)

| Data | Storage | Envelope |
|---|---|---|
| Notes, journals, tasks, goals, events, chat, memory, fitness, health, nutrition, training, scans, trash, six-pack, finance documents | `app_state.value` | AES-256-GCM `{v, ct}`; AAD binds the state key |
| Event photos/videos | R2 `event-media/<user>/<id>` | AES-GCM ciphertext |
| Progress/body photos | R2 `body-photos/<user>/<id>.jpg` | AES-GCM ciphertext |
| Vault metadata | `app_state['meos.crypto']` | public salts + wrapped DEK + check token; no plaintext key |

The Worker does not have the DEK. A full D1 + R2 dump does not reveal these payloads.

### Server-visible (necessary for functionality, not E2E)

| Data | Why | Protection |
|---|---|---|
| Username, password hash, sessions, MFA state | authentication | salted PBKDF2 (optionally peppered), hashed session tokens, TOTP, 30-day/14-day idle session limits |
| Device names/platforms/last seen | device list before unlock | scoped by `user_id`, no vault data |
| AI provider keys, TOTP secret | server must call the provider / verify codes | AES-256-GCM with `MEOS_SECRETS_KEY` (key ring) |
| Model routing (`meos.ai.routes`) | app sync, non-secret | plaintext by design |
| Security audit events | detection/response | metadata only, salted IP hash, 180-day retention |
| Media object keys/sizes | storage quota, listing | scoped by `user_id`; no public URLs |
| Password hashes / session hashes | auth | see above |

### Third-party AI

When ChatGPT asks for a note, the **gateway** decrypts it and returns it. ChatGPT/OpenAI processes that
plaintext. MeOS cannot make a third-party model unsee data it was asked to read. This is stated on the
consent screen and in [`MCP_SETUP.md`](MCP_SETUP.md). Grant the smallest scopes and disconnect when done.

### What the server can infer

Even without plaintext, D1 reveals: number of state rows per module, approximate sizes, update times,
device names, session times, audit metadata, AI model ids, and the wrapped-key parameters. This is
metadata leakage, not content. It is documented rather than hidden.

---

## 3. Authentication and sessions

- **Login password**: PBKDF2-SHA256, versioned `v3` (peppered) / `v2` / legacy scrypt. The pepper is
  `MEOS_PASSWORD_PEPPER`; it is deliberately separate from the rotating secrets key. Work factor is
  configurable (`MEOS_PBKDF2_ITERATIONS`, default 10k for the Workers free tier). A DB-only leak without
  the pepper cannot verify guesses.
- **Vault passphrase**: separate, never sent to the server, PBKDF2-HMAC-SHA256 **600,000** rounds on-device
  (CommonCrypto), AES-256-GCM. Argon2id is not implemented; see [`ENCRYPTION.md`](ENCRYPTION.md).
- **Sessions**: random 256-bit cookie, only a SHA-256 hash stored in D1. `HttpOnly`, `Secure` in
  production, `SameSite=Strict`, 30-day absolute / 14-day idle expiry. Legacy plaintext rows are upgraded
  on first use. Password change revokes every other session.
- Full details: [`docs/AUTHENTICATION.md`](docs/AUTHENTICATION.md).
- **MFA**: optional TOTP (RFC 6238), encrypted secret, one-time recovery codes (hashed, burned on use).
  Login, password change, re-auth and AI-key changes require the code when enabled. The MCP gateway can
  sign in unattended only if `MEOS_MCP_MFA_SECRET` holds the same TOTP seed; the gateway host is already
  trusted with the vault passphrase. Passkeys/WebAuthn are a documented follow-up, not a half-built
  endpoint.
- **Re-authentication**: export, MFA enrollment/disable, secret rotation, session revocation and AI
  provider add/delete require the login password (and MFA) with the request. A merely “recent” session is
  not enough for these actions, so a cookie stolen in the first five minutes cannot use them.
- **Rate limiting**: durable login attempts per username and IP (10 / 15 min); per-isolate burst limits on
  state/media/AI/export/OAuth/admin endpoints. Run one Worker isolate expectation is documented: the
  durable login/ai budgets are the primary control.
- **Signup**: closed after the first account unless `MEOS_ALLOW_SIGNUP=true`. Set
  `MEOS_SETUP_TOKEN` on a fresh deployment so only the operator can create the first account; it is sent
  as `setupToken` with the first registration.

---

## 4. Authorization

- Every authenticated query is scoped by `user_id`; there is no RLS fallback because D1 has no RLS. The
  Worker is the only DB client, and every route reads the user from the verified session, never from a
  request field.
- State keys are allowlisted. Media keys are `body-photos/<user>/` or `event-media/<user>/`; IDs reject
  `/`, `..` and traversal. AI credential updates/deletes include `user_id`.
- Once `meos.crypto` exists, the state route refuses plaintext for module keys (anti-downgrade). It also
  structurally validates the vault metadata and sealed envelopes.
- MCP tools have per-module granular scopes (`meos.finance.read`, etc.). The server enforces them before
  any record lookup; `tools/list` is filtered. The model is never the authorization layer.

---

## 5. API hardening

- CSRF: unsafe `/api/*` requests are rejected when `Origin` is not an exact trusted origin or
  `Sec-Fetch-Site: cross-site`. Native clients send no Origin. `SameSite=Strict` and JSON-only bodies are
  additional layers.
- CORS: denied by default; exact `MEOS_CORS_ORIGINS` allowlist only.
- Headers: `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`,
  `Permissions-Policy`, COOP/CORP, HSTS on HTTPS, `noindex`, `private, no-store` on API responses.
- CSP: SvelteKit `mode: auto`, default-deny (`default-src 'self'`, no third-party scripts, `frame-ancestors
  'none'`, `object-src 'none'`).
- Input: byte caps before parsing, schema validation, bounded pagination, media MIME/ID checks, no raw SQL
  or dynamic identifiers except fixed DDL.
- Errors: SvelteKit generic 500 in production; the server error hook logs only status/name, not bodies.
- Rate limits and budgets: see `src/lib/server/security.ts`, `aiBudget.ts`, `voiceBudget.ts`.

---

## 6. Database and storage

- **D1**: single-tenant schema with `user_id` on every user-owned table. No `SECURITY DEFINER` functions,
  no Postgres RLS, no service-role key in the app. Migrations are additive and non-destructive; sessions
  gain columns lazily. Backups are encrypted exports; see [`docs/BACKUP.md`](docs/BACKUP.md).
- **R2**: private bucket, no public URL, no anonymous access. Full details:
  [`docs/STORAGE_SECURITY.md`](docs/STORAGE_SECURITY.md). Every read signs a GET URL for 10 minutes
  after a session + ownership check. Media is ciphertext for event/body photos; uploads capped per object
  and per account. There is no server-side image parser on the media path, so malformed uploads cannot
  execute; the client decrypts its own files.
- **Secrets**: server secrets live in Wrangler (`wrangler secret put`) or a secret manager; never in
  frontend bundles. `.env*` is gitignored except examples. Production, staging and dev use separate
  credentials. Git history is scanned by CI.

---

## 7. Logging and monitoring

- Audit events are metadata only: login success/failure, MFA, re-auth, session revoke, state/module key
  writes, media add/delete, AI key changes, export, secret rotation, CSRF blocks, MCP OAuth/tool calls.
- Never logged: passwords, passphrases, tokens, API keys, ciphertext, note/journal text, amounts, account
  numbers, full request bodies.
- IPs are salted hashes; user agents are truncated hashes in the MCP log. Retention is 180 days for D1 and
  5 MB × 3 rotations for the MCP JSONL.
- Dashboard: `/api/security/events` (native Security screen) and the MCP `/admin` page. Alerts surface
  repeated failed logins and refused cross-site requests.

---

## 8. Backups and recovery

- D1 Time Travel is the first-line recovery. Offsite backups are encrypted `age` exports; see
  [`docs/BACKUP.md`](docs/BACKUP.md).
- R2 media is ciphertext; copy it separately if you need a full restore. A D1 backup alone restores the
  module JSON, not the photos.
- **Losing the vault passphrase and the recovery code means the encrypted modules are unrecoverable.**
  There is no server-side escrow and no "reset encryption" that preserves data. Losing only the login
  password is recoverable through the app/session, not by email (there is no email recovery channel).
- Backups never weaken the model: they preserve ciphertext + `meos.crypto` + wrapped keys. Restoring them
  does not give the server a key.

---

## 9. MCP / AI boundary

The gateway is a separate security domain:

- OAuth 2.1 authorization code + PKCE S256, dynamic client registration, exact redirect URIs, audience
  binding, 15-minute access tokens, rotating refresh tokens with reuse detection, RFC 7009 revocation.
- Admin consent requires a dedicated MCP admin password and explicit module checkboxes; default is profile
  read only.
- Tool scopes are granular; destructive/finance writes need `confirm: true`; write tools support
  idempotency keys; prompt-injected content is marked untrusted and cannot change server permissions.
- The gateway holds the vault passphrase in its environment. Protect that host. It is not exposed to
  ChatGPT; only the HTTPS tunnel is.
- No SQL, filesystem, shell, arbitrary URL or service-role tool exists, and adding one is not a config
  option.

See [`MCP_SETUP.md`](MCP_SETUP.md) and [`docs/AI_PERMISSION_MATRIX.md`](docs/AI_PERMISSION_MATRIX.md).

---

## 10. Deployment and operations

Use [`docs/DEPLOYMENT_CHECKLIST.md`](docs/DEPLOYMENT_CHECKLIST.md). Minimum:

1. `MEOS_SECRETS_KEY` = 32 random bytes, base64; set `MEOS_PASSWORD_PEPPER` and
   `MEOS_MFA_RECOVERY_PEPPER` to separate stable values.
2. Keep `MEOS_ALLOW_SIGNUP` unset after first-run.
3. Set `MEOS_TRUSTED_ORIGINS` only if a browser client exists; otherwise leave CORS empty.
4. Run `bun run check && bun run test && bun run build`, the MCP suites, and `scripts/security-scan.sh`.
5. Deploy with `wrangler deploy`; verify `/api/me` is 401 without a cookie and security headers are present.
6. Rotate secrets by adding a new key to `MEOS_SECRETS_KEYS`, switching `MEOS_SECRETS_KEY_ID`, deploying,
   then calling `/api/security/rotate-ai-keys` with a fresh re-auth. Keep the old key until it succeeds.
7. Back up with `AGE_RECIPIENT=... ./scripts/backup-d1.sh` and test a restore into a local D1.

---

## 11. Incident response

Summary; full procedure in [`docs/INCIDENT_RESPONSE.md`](docs/INCIDENT_RESPONSE.md).

1. **Contain**: revoke sessions (`DELETE /api/security/sessions` after re-auth), disconnect the MCP client
   in `/admin`, stop the tunnel/gateway, roll the Cloudflare API token if exposed.
2. **Assess**: `/api/security/events`, MCP audit log, Cloudflare logs, D1 Time Travel. Preserve evidence;
   do not delete rows.
3. **Eradicate**: rotate login password, vault passphrase + recovery code (re-wraps the DEK), AI provider
   keys, `MEOS_SECRETS_KEY` (add new key, rotate, retire old), MCP admin password, OAuth clients.
4. **Recover**: restore from an encrypted backup only after verifying its age and integrity; re-enable
   clients with minimum scopes.
5. **Learn**: write down what was exposed. If the DEK/passphrase was exposed, assume all E2E data was
   exposed; rotation of the passphrase does not re-encrypt old ciphertext.

Report a vulnerability privately to the owner (Berjil) via the repository's private security advisory or
`berjiljacob@gmail.com`. Do not open a public issue with exploit details. There is no bug bounty.

---

## 12. Known limitations (read these)

| Limitation | Consequence | Mitigation / plan |
|---|---|---|
| Argon2id not implemented on-device | PBKDF2 600k is the KDF; weaker against GPU guessing than Argon2id at equal memory | Strong unique passphrase; Argon2id via a vetted library is a planned upgrade |
| No passkeys/WebAuthn | Phishing-resistant login not available | TOTP MFA; WebAuthn is a planned client feature |
| D1 has no RLS | A bug in a query could cross users if `user_id` predicate is forgotten | Every route reviewed; tests + code review; single-owner deployment |
| Login KDF default 10k on free tier | Lower offline work factor than a paid plan | Dedicated pepper; rate limits; raise `MEOS_PBKDF2_ITERATIONS` on paid Workers |
| In-memory burst limits per isolate | Effective limit multiplies across isolates | Durable login/AI limits are the primary controls |
| MCP gateway holds vault passphrase in env | Host compromise = vault compromise | Trusted host, disk encryption, 0600 env, loopback bind, no untrusted code |
| AI provider sees retrieved plaintext | Third-party processing | Explicit consent, per-module scopes, data minimization, disconnect |
| DEK rotation not automated | Passphrase/recovery re-wrap works; ciphertext stays under the same DEK | Documented manual export/re-encrypt procedure is a follow-up |
| `meos.crypto` write is session-authenticated, not password-proven | A stolen session can cause a vault lockout (not decrypt data) | Client verifies current passphrase before re-wrap; re-auth window; audit |
| Journal module absent | `meos.journal.*` is not grantable | Notes + memory are the real surfaces; do not fake a scope |
| No email account recovery | Lost login password needs an existing session/device | Keep a device signed in and the recovery code offline |
| Dev dependencies (Vite/Vitest) carry advisories | Local dev server only; not in the Worker bundle | Production audit is clean; upgrade tracked separately |

---

## 13. Security evidence

The following are reproducible:

```bash
cd apps/api && bun run check && bun run test && bun run build
cd mcp/meos && npm run typecheck && npm test
cd mcp/diet && bun test
cd mcp/stuff && bun test
./scripts/security-scan.sh           # production audits + secret grep
cd apps/apple && xcodegen generate && xcodebuild -scheme MeOS-macOS build
```

Latest results and the acceptance-criteria checklist are in
[`docs/SECURITY_TEST_EVIDENCE.md`](docs/SECURITY_TEST_EVIDENCE.md). A checkbox is not proof; the evidence
column points to the test or command that produced it.
