# MeOS data classification

This is the authoritative map of what MeOS stores, where it lives, and who can read it. It is deliberately
more specific than “sensitive vs not”, because the encryption and MCP scopes depend on the class.

## 1. Classes

| Class | Examples | Storage | Encrypted by | Readable by |
|---|---|---|---|---|
| **C4 — vault secret** | Finance ledger (accounts, transactions, bank names, balances, investments, liabilities, budgets, goals, statements metadata), notes, journal-like text, health metrics, workouts, diet, events, memory, chat, scans, recycle-bin payloads, profile private fields, MCP connector registry (token hashes, scopes, expiry; never raw tokens) | D1 `app_state.value` | Client DEK / per-key HKDF; AES-256-GCM | Client with unlocked vault |
| **C4 — private media** | Event photos/videos, body/progress photos, document-like attachments | R2 `event-media/<user>/…`, `body-photos/<user>/…` | Client DEK; AES-GCM + per-id AAD | Client with DEK; 10-min signed URL after session check |
| **C3 — vault key material** | `meos.crypto` wrapped DEK, salts, check token | D1 `app_state['meos.crypto']` | Public by design; wrapped under passphrase/recovery | Anyone with DB can attempt offline passphrase guessing; no plaintext key |
| **C3 — server secret** | AI provider keys, TOTP seed | D1 `ai_credentials.secret`, `user_mfa.secret` | Worker AES-256-GCM key ring | Worker with `MEOS_SECRETS_KEY`; never returned masked/plain |
| **C3 — credentials** | login password hash, session hash, MFA recovery-code hashes | D1 `users.password_hash`, `sessions.token_hash`, `mfa_recovery_codes.code_hash` | one-way KDF/hash + pepper | verification only |
| **C2 — account metadata** | username, device name/platform/last-seen, session timestamps/UA, AI key label/masked, AI routing, module key names/sizes, media object names/counts | D1 metadata tables, plaintext `meos.ai.routes` | not E2E | Worker/owner; no note or money content |
| **C2 — audit metadata** | event name, outcome, salted IP hash, UA hash/string, module key, counts | D1 `security_events`, MCP `audit.log` | not E2E | owner / gateway host |
| **C1 — public** | landing page, anatomy data, MCP metadata/health | static / Worker | n/a | anyone |

## 2. What is end-to-end encrypted

- Every `app_state` key except `meos.crypto`, `myos.crypto`, `meos.ai.routes`, `myos.ai.routes`.
- The entire finance ledger document (`meos.finance`) — accounts, transactions, balances, investments,
  liabilities, budgets, goals, audit history.
- The MCP connector registry (`meos.mcp`) — only SHA-256 token hashes, short prefixes, scopes and expiry.
  Raw bearer tokens are shown once in the app and are never stored or uploaded.
- Event/body media bytes in R2.
- Fold tokens are sealed under the DEK and stored in Keychain / encrypted state.
- Backups preserve the ciphertext and wrapped key material; they do not add a server-readable copy.

The Worker stores ciphertext and cannot decrypt these classes. This is verified by the
`stateKeys`/`secrets` tests, the restore drill, and the D1 inspection procedure.

## 3. What is necessarily server-visible

| Data | Why | Mitigation |
|---|---|---|
| username, password hash, session hash | authentication | PBKDF2/Argon2id + pepper, hash-only sessions, MFA, rate limits |
| AI provider key / TOTP seed | server calls provider / verifies TOTP | AES-GCM key ring, masked output, re-auth |
| `meos.crypto` | unlock metadata | wrapped DEK; no plaintext key; server validates shape only |
| `meos.ai.routes` | model routing sync | contains key ids/model names, not secrets |
| device/session metadata | device list before unlock | owner-scoped, no vault data |
| module key names, sizes, timestamps | sync/ETag, quota | metadata only |
| audit events | detection/forensics | redacted, salted, retention |
| media names/counts | quota/listing | owner-scoped; bytes ciphertext |
| backup status | dashboard | timestamp/kind only |

## 4. Metadata leakage (documented, not hidden)

A database-only attacker can learn: number of accounts/transactions is not visible as rows because finance
is one encrypted document; but module names, document sizes, update times, device names, session times,
AI model routing, key ids, media object sizes and audit metadata are visible. A `meos.mcp` document reveals
that MCP connectors exist and its approximate size, but not a token, prefix or scope. They cannot read note
text, transaction payees/amounts, bank names, health values or media bytes.

## 5. Retention

| Data | Retention |
|---|---|
| `app_state` | until user deletes/purges; recycle bin 30 days |
| Finance ledger | until user deletes; no MCP delete tool |
| media | until recycle-bin purge / explicit delete |
| sessions | 30 days absolute, 14 days idle |
| `security_events` | 180 days (opportunistic prune) |
| MCP audit | current + 3 rotations at 5 MB |
| backup exports | operator schedule (suggest 14 daily / 8 weekly / 12 monthly) |
| logs | Cloudflare retention per plan; no payloads |

## 6. Access rule summary

- Client/UI: full C4 after unlock; Keychain DEK `ThisDeviceOnly`.
- Worker: C3/C2 metadata; never C4 plaintext.
- MCP gateway: C4 only for modules the OAuth client was granted; returns the minimum tool response.
- ChatGPT/other AI provider: receives only C4 fields returned by an authorized tool; that is an explicit
  disclosure outside the E2EE boundary.
- D1/R2 administrator: ciphertext + C2/C3 metadata; no plaintext C4.
- Backup operator: ciphertext + C3/C2; age/backup passphrase required to restore.

See `ENCRYPTION.md` for formats and `docs/AI_PERMISSION_MATRIX.md` for AI scopes.
