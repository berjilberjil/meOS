# Authentication and session security

MeOS has two independent credentials and several machine identities:

| Identity | Secret | Used for | Stored |
|---|---|---|---|
| Login password | user-chosen | app/API session | PBKDF2 `v3` (peppered) or optional Argon2id `v4`; `v2`/legacy scrypt still verify |
| Vault passphrase | user-chosen, never sent | decrypting the E2E vault | PBKDF2 600k on-device; wrapped DEK in `meos.crypto` |
| MeOS session | 256-bit random cookie | app/API requests | only SHA-256 hash in D1 |
| TOTP seed | 160-bit base32 | second factor at login | AES-GCM encrypted in D1 |
| MFA recovery codes | 60-bit Crockford codes | one-time second factor | SHA-256 hash in D1 |
| MCP OAuth access token | opaque 256-bit | MCP requests | SHA-256 hash in the gateway |
| MCP refresh token | opaque 256-bit | rotate access | SHA-256 hash, rotation + reuse detection |
| MCP admin password | operator secret | consent/dashboard | env, constant-time compare |
| AI provider key | provider-issued | AI calls | AES-GCM encrypted in D1 |

The login password never derives the vault key. Changing it does not change the DEK or the passphrase.

## 1. Login

1. `POST /api/auth/login` with username/password (and `code` if MFA).
2. Per-username and per-IP throttle: 10 failures / 15 minutes (D1-backed).
3. Unknown users get a dummy PBKDF2 derivation, so timing does not reveal existence.
4. Wrong password → generic 401; audit `login/failure` with no username.
5. Correct password + MFA enabled:
   - no code → `mfaRequired: true`, no session;
   - wrong code → 401, failed attempt;
   - TOTP or unused recovery code → session.
6. Session: random 256-bit token; DB stores SHA-256; cookie `meos_session`, `HttpOnly`, `Secure` in
   production, `SameSite=Strict`, 30-day absolute / 14-day idle.
7. Successful login upgrades a legacy/v2/v3 hash to the configured current format. `v4` is Argon2id
   (19 MiB, t=2 by default), enabled with `MEOS_PASSWORD_KDF=argon2id` on a Worker plan with enough CPU;
   the default remains PBKDF2 `v3` because the free tier's 10 ms CPU cap cannot run Argon2id.
8. `MEOS_PASSWORD_PEPPER` is hashed into the password before either KDF. Argon2id is never a replacement
   for the pepper: a DB-only leak still lacks the server-side value.

`MEOS_ALLOW_SIGNUP` is the only way to create a second account after the first; it is closed by default.
`MEOS_SETUP_TOKEN` can gate the first account on a fresh deployment.

## 2. Sessions

- `hooks.server.ts` resolves the cookie via `findSession`; no route sees a raw token.
- Legacy plaintext session rows are upgraded on first use; other legacy rows are deleted on
  “sign out other devices”.
- `GET /api/security/sessions` lists public ids, creation, last seen, expiry, UA, current marker.
- `DELETE /api/security/sessions` revokes every other session; `DELETE /api/security/sessions/<id>` revokes
  one. Both require a fresh re-auth.
- Password change revokes every other session. MFA enable/disable also revokes others.
- Logout deletes this session and clears the cookie.

## 3. MFA (TOTP)

- Optional; enable via Security → Two-factor.
- Server generates a 20-byte secret, shows it and the `otpauth://` URL once, plus 10 recovery codes; the
  secret is encrypted with `MEOS_SECRETS_KEY`, codes are hashed with `MEOS_MFA_RECOVERY_PEPPER`.
- 6 digits, 30s step, SHA-1 (RFC 6238), ±1 step tolerance.
- Required at login, password change, re-auth, AI provider add/replace/delete.
- Recovery codes are single-use and burned.
- Enabling/disabling requires a fresh re-auth; disabling also requires a current code.
- The MCP gateway can sign in unattended only if `MEOS_MCP_MFA_SECRET` holds the same seed.

## 4. Re-authentication

`POST /api/auth/reauth` verifies the login password (and MFA) and marks the session fresh for 5 minutes.
The highest-risk actions require the password explicitly (a fresh login alone is not enough against a
cookie stolen in the first five minutes):

- exporting the vault,
- enrolling/disabling MFA,
- rotating server secrets,
- revoking sessions,
- changing vault metadata (`meos.crypto` replacement, except first-run setup),
- adding/replacing/deleting AI provider keys.

The proof is per-session; another device must re-prove. The password is supplied with the request, not
inferred from a recent login, so a session cookie stolen immediately after sign-in cannot perform these
actions.

## 5. Recovery

| Lost | Recovery |
|---|---|
| Login password | existing signed-in device/session; no email reset |
| Vault passphrase | recovery code, then set a new passphrase |
| Vault passphrase + recovery code | unrecoverable; restore a backup **and** find the matching passphrase/code |
| MFA device | a remaining recovery code; then re-enroll |
| MCP admin password | rotate env, restart gateway; existing OAuth clients remain until revoked |
| AI key / `MEOS_SECRETS_KEY` | re-enter provider keys / add new ring key and rotate |

There is no server-side escrow or “reset encryption” that preserves vault data.

## 6. MCP / AI authentication

See [`MCP_SETUP.md`](../MCP_SETUP.md). Summary: OAuth 2.1 authorization code + PKCE S256, dynamic client
registration with exact redirects, public clients only, audience-bound 15-minute access tokens, rotating
refresh tokens with reuse detection, RFC 7009 revocation, consent gated by a separate admin password,
per-module scopes. Static bearer tokens remain for local/stdio clients.

## 7. Not implemented

- **Passkeys/WebAuthn**: no platform authenticator flow yet. TOTP is the second factor; passkeys are a
  planned follow-up.
- **Email password reset**: single-owner design, no email channel. Keep a device signed in.
- **Hardware security keys**: not integrated.
- **Per-device session binding**: sessions are cookie-based, not bound to a device key. A stolen cookie is
  mitigated by hash-only storage, expiry, re-auth and revocation, but is still a bearer credential.
- **Argon2id on-device**: the vault passphrase still uses PBKDF2-HMAC-SHA256 600k. Argon2id is available
  for the server login hash only when enabled; moving the vault KDF requires a vetted Swift Argon2id
  implementation and a versioned migration (and a matching Node implementation for the MCP gateway).

These are listed in `SECURITY.md` §12 rather than implied to exist.
