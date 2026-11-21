# API security

The API is a headless JSON service. Every private route resolves the user from the `meos_session` cookie in
`hooks.server.ts`; no route accepts a `user_id` or account from the caller.

## 1. Global controls

| Control | Implementation |
|---|---|
| Authentication | session cookie → `findSession()` (hash lookup, expiry, idle, revocation) |
| CSRF | unsafe `/api/*` requests require no `Origin` or an exact trusted origin; `Sec-Fetch-Site: cross-site` rejected; `SameSite=Strict` |
| CORS | denied by default; exact `MEOS_CORS_ORIGINS` only |
| Body caps | global 100 MB pre-check; per-route 2 KB–81 MB |
| Rate limits | durable login attempts; per-isolate burst limits on state/media/AI/export; D1 AI/voice budgets |
| Errors | SvelteKit generic production error; `handleError` logs status/name only |
| Headers | HSTS, CSP, X-Frame-Options, nosniff, Referrer-Policy, COOP/CORP, Permissions-Policy, no-store |
| Audit | login/MFA/reauth/export/keys/sessions/state/media/secret rotation; metadata only |
| IDOR | every query filters `user_id`; media keys are user-prefixed; wrong ids are 404 |

## 2. Endpoint inventory

### Public

| Method | Path | Data | Controls |
|---|---|---|---|
| GET | `/` | static landing | prerendered, no auth, no data |
| GET | `/api/anatomy` | static body-map JSON | public, long cache |
| GET | `/healthz` (MCP) | `{ok}` | no data |

### Authentication

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/auth/register` | none, first-run only | 8KB cap, username regex, password ≥8, closed after first account, audit |
| POST | `/api/auth/login` | none | 4KB, per-user+IP 10/15min, dummy PBKDF2, optional TOTP, audit |
| POST | `/api/auth/logout` | cookie | deletes only this session, audit |
| POST | `/api/auth/password` | cookie + current password (+MFA) | revokes other sessions, reauth marked, audit |
| POST | `/api/auth/reauth` | cookie + password (+MFA) | 5-minute proof window, audit |
| GET | `/api/auth/mfa` | cookie | status only, no secret |
| POST | `/api/auth/mfa/setup` | cookie + password (+MFA) | returns secret/otpauth/recovery codes once, audit |
| POST | `/api/auth/mfa/enable` | cookie + fresh reauth | verifies first TOTP, audit |
| POST | `/api/auth/mfa/disable` | cookie + password + code | deletes factor, revokes other sessions, audit |

### State

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/state` | cookie | ETag/304, 180/min, only own rows |
| PUT | `/api/state/[key]` | cookie | allowlisted key, 1.9MB cap, meta/envelope validation, anti-downgrade, audit |
| DELETE | `/api/state/[key]` | cookie | own key only, 60/min, audit |

`meos.crypto` and `meos.ai.routes` are the only plaintext keys. Once a vault exists, every other module
value must be a sealed envelope; plaintext is refused with 400.

### AI

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET/POST | `/api/ai/keys` | cookie; POST + password (+MFA) | masked list; live validation; encrypted at rest; audit |
| PATCH/DELETE | `/api/ai/keys/[id]` | cookie; secret replace/delete + password (+MFA) | ownership check; generic provider errors; audit |
| POST | `/api/ai/keys/[id]/check` | cookie | revalidates, 30/min, no secret returned |
| GET/PUT | `/api/ai/routes` | cookie | non-secret routing, 60/min, audit |
| POST | `/api/chat`, `/parse`, `/parse-image`, `/plan`, `/suggest`, `/news`, `/categorize`, `/categorize-event`, `/memory` | cookie | 120/min AI burst + durable budget; bounded inputs; provider sees the prompt |
| GET | `/api/macro` | cookie | cached, FRED + model, per-user row |
| POST | `/api/voice/speak` | cookie | 60/min + durable voice budget; text cap |

The chat route declares tools supplied by the client, but no tool executes on the server; the client runs
them against its unlocked vault. This keeps the zero-knowledge model intact.

### Devices / media

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET/POST | `/api/devices` | cookie | device metadata only, 8KB, id regex |
| PATCH | `/api/devices/[id]` | cookie | display name only; ownership |
| GET/POST | `/api/body-photos` | cookie | list/sign or upload; 60/30 per min; user prefix; 15MB object; ciphertext |
| DELETE | `/api/body-photos/[id]` | cookie | user prefix; 60/min; audit |
| GET/POST | `/api/event-media` | cookie | sign ≤200 ids or upload; 120/30 per min; 60MB object; ciphertext |
| DELETE | `/api/event-media/[id]` | cookie | user prefix; 60/min; audit |

Signed GET URLs live **600 seconds** and are only minted after the session + prefix check. R2 is private;
there is no anonymous or cross-user URL.

### Security / export

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/security/sessions` | cookie | own sessions, public ids only |
| DELETE | `/api/security/sessions` | cookie + password (+MFA) | revoke every other session, audit |
| DELETE | `/api/security/sessions/[id]` | cookie + password (+MFA) | revoke one, ownership, audit |
| GET | `/api/security/events` | cookie | own audit rows, no payloads |
| POST | `/api/security/rotate-ai-keys` | cookie + password (+MFA) | re-encrypt AI/TOTP secrets under active key, audit |
| POST | `/api/export` | cookie + password (+MFA) | encrypted state + masked metadata + media counts; 3/hour; audit |

## 3. Input/output rules

- IDs: bounded regex; media ids reject `/`, `.`, `..`; device ids `[a-z0-9-]{8,64}`.
- Dates: `YYYY-MM-DD`; ranges bounded.
- Images: base64 length checked before decode; object caps; no server-side image parser on the media path.
- Pagination: bounded limit/cursor in MCP; API lists are capped by query.
- Errors: no stack, SQL, file path, provider response, or secret. Provider failures become “The provider
  rejected that key.”
- Output: masked keys only; session tokens never returned; audit IP is hashed; media is signed URLs only.

## 4. Verification

- `apps/api/src/lib/server/security.test.ts` — origin/CORS/headers/limiter/audit redaction.
- `apps/api/src/lib/server/stateKeys.test.ts` — allowlist/meta/envelope.
- `mcp/meos/tests/oauth.test.ts` — 401 challenge, audience, scope, revoke.
- Manual: `curl -i https://.../api/me` → 401 + headers; `curl -i -X PUT` with `Origin: https://evil` → 403;
  D1 `app_state.value` for a note → `{v,ct}`.

## 5. Residual

- Per-isolate burst limits are not global. Durable login/AI limits are the hard ceilings.
- The AI routes necessarily send user-provided context/images to the configured provider.
- A stolen session can read ciphertext and replace `meos.crypto` (lockout), but cannot decrypt modules.
