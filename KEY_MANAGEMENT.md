# MeOS key management

This document is the operational counterpart to `ENCRYPTION.md`. It lists every key, where it lives, how it
is versioned, and how it is rotated or destroyed.

## 1. Vault hierarchy

```
passphrase ──PBKDF2-SHA256(600k, passSalt)──▶ KEK_pass ──AES-256-GCM──▶ wrappedByPass
recovery   ──PBKDF2-SHA256(600k, recSalt)───▶ KEK_rec  ──AES-256-GCM──▶ wrappedByRecovery

random 32-byte DEK ─┬─ v1: AES-GCM(DEK, AAD=state key)
                    └─ v2: HKDF(DEK, "meos.data.v2:<key>") ─▶ AES-GCM(subkey, AAD="meos.envelope.v2:<key>")

media: AES-GCM(DEK, AAD="event-media:<id>" / "body-photo:<id>")
backup: PBKDF2-SHA256(600k, backupSalt) ─▶ AES-GCM(AAD="meos.export.v1")
```

- **DEK**: generated with `SecRandomCopyBytes` (32 bytes). Never uploaded; cached only in the
  Keychain as `WhenUnlockedThisDeviceOnly`.
- **`meos.crypto`**: public KDF parameters, salts, wrapped DEK copies and check token. No plaintext key.
- **Versioning**: `CryptoMeta.v`; `dataVersion` for state envelopes (1/2); envelope `v` (1/2);
  `CryptoMeta.kdf` identifies the passphrase KDF. Older clients read v1; new vaults write v2.
- **Integrity**: GCM tag; AAD binds ciphertext to its state key/media id; unlock validates the sealed check
  token before adopting a candidate DEK.
- **Nonces**: 96-bit random per encryption from the platform CSPRNG. Never reuse a nonce with a key.

## 2. Vault lifecycle

| Operation | What changes | What does not |
|---|---|---|
| Create vault | new DEK, salts, wrapped copies, check token | existing plaintext migration must seal every module (done in order; see SEC-15) |
| Change passphrase | new passSalt, new KEK, new `wrappedByPass` | DEK and ciphertext unchanged; recovery unchanged |
| New recovery code | new recoverySalt/KEK, new `wrappedByRecovery` | DEK/ciphertext unchanged; old code invalid |
| Change DEK (full rotation) | new DEK, re-seal every envelope/media, re-wrap meta | requires offline maintenance; synthetic drill in `scripts/key-rotation-drill.ts`; not a one-click production operation |
| Delete vault | **not exposed** via the state API | `meos.crypto` deletion is blocked; owner must use a deliberate offline wipe/export procedure |
| Lost device | revoke sessions; KTDEK is device-only | other devices re-derive DEK from passphrase/recovery |

### Passphrase/recovery rotation (implemented)
Settings → Change encryption passphrase / New recovery code. Both require the current vault passphrase
(client verifies it) and a fresh login password+MFA proof (server verifies the session owner). The DEK does
not change.

### DEK rotation (proven offline, not automated)
A production DEK rotation is an offline maintenance operation:
1. Take and verify an encrypted backup.
2. Stop all clients and the MCP gateway.
3. Decrypt the state on a trusted machine with the current DEK.
4. Generate a new DEK, re-seal every `app_state` value and every R2 object with new AADs/objects.
5. Write a new `meos.crypto` wrapped under the passphrase + a new recovery code.
6. Verify a sample of every module and media, then re-enable clients.
7. Destroy the old backup/DEK copies per retention policy.

The repository includes `scripts/key-rotation-drill.ts`, which verifies the rewrap and re-encryption
primitives on synthetic data. The full production migration is deliberately **not** automated because a
partial cross-key write can make old ciphertext unreadable; it must be run under the backup/rollback plan.

## 3. Server-held secrets

- **Key ring** `MEOS_SECRETS_KEYS` JSON; active id `MEOS_SECRETS_KEY_ID`. Ciphertext
  `v2:<key-id>:base64(iv‖ct‖tag)` with AAD `meos.secret.v2:<key-id>`.
- A 32-byte key is required for new encryption; a weak legacy passphrase is decrypt-only unless
  `MEOS_ALLOW_WEAK_SECRETS_KEY=true` (not recommended).
- Encrypts: AI provider keys, TOTP seed.
- Rotation: add new key → activate → deploy → `POST /api/security/rotate-ai-keys` with password+MFA →
  remove old key only after success. Never remove a key still referenced by ciphertext.
- Legacy ciphertext (raw base64, no AAD) is still decryptable with the ring; it is re-encrypted by rotation.

## 4. Password / MFA credentials

| Credential | Algorithm | Pepper | Notes |
|---|---|---|---|
| Login password | PBKDF2-SHA256 v3 (10k default) or optional Argon2id v4 (19 MiB, t=2) | dedicated `MEOS_PASSWORD_PEPPER` HMAC before KDF | v4 only on Workers plans with enough CPU; old hashes verify and upgrade |
| Vault passphrase | PBKDF2-SHA256 600k on-device | none (salt only) | Argon2id on-device is a documented future migration |
| MFA TOTP | RFC 6238, 30s, 6 digits | n/a | seed encrypted with server key ring |
| MFA recovery codes | 60-bit Crockford codes, SHA-256 + `MEOS_MFA_RECOVERY_PEPPER` | separate stable pepper | single-use |
| Session tokens | 256-bit random; SHA-256 at rest | n/a | 30d/14d; revoke |

Pepper rotation consequences: changing `MEOS_PASSWORD_PEPPER` invalidates v3 hashes (v2/legacy still
verify and upgrade); changing `MEOS_MFA_RECOVERY_PEPPER` invalidates unused recovery-code hashes. Keep both
stable and backed up separately from the database.

## 5. MCP / OAuth keys

- **App-managed connector tokens**: 256-bit random, prefixed `meos_mcp_`, shown once in the app. Only the
  SHA-256 hash and a short prefix are stored in the encrypted `meos.mcp` document; the raw token never
  reaches the server or another device. Revocation sets `revoked: true`; the gateway's 10-second cache is
  the maximum delay. These are bearer credentials, not encryption keys: they cannot decrypt the vault.
- Client registrations: public `client_id`, exact redirect URIs; no client secret (public clients + PKCE).
- Authorization codes: 256-bit, SHA-256 at rest, 5-minute TTL, single use, PKCE S256 bound.
- Access tokens: 256-bit opaque, SHA-256 at rest, 15-minute TTL, audience-bound to `<public>/mcp`.
- Refresh tokens: 256-bit opaque, SHA-256 at rest, 30-day TTL, rotate on use; reuse revokes the family.
- Admin password: `MEOS_MCP_ADMIN_PASSWORD`, env only; gates consent + `/admin`; not a vault key.
- MFA seed for the gateway: `MEOS_MCP_MFA_SECRET` (same TOTP seed) when login MFA is enabled.
- Store file: `~/.meos/mcp/oauth.json`, mode 0600, dir 0700; contains hashes + public client metadata.
- Revocation: dashboard Disconnect deletes tokens/codes; RFC 7009 endpoint for one token.

## 6. Backup and recovery keys

- `age` identity for D1 exports: keep offline, separate from the backup files.
- Native encrypted export: PBKDF2 600k + AES-GCM; the backup passphrase is user-chosen and not stored.
- Losing the age identity or native backup passphrase makes that backup unrecoverable; this is deliberate.
- Restore drill: `scripts/restore-drill.ts` (synthetic D1 + state + media, tamper rejection).

## 7. Key-loss matrix

| Lost | Result | Recovery |
|---|---|---|
| Login password | cannot sign in | signed-in device/session; no email reset |
| Vault passphrase | vault locked | recovery code → set new passphrase |
| Passphrase + recovery code | E2E data unrecoverable | restore a backup + matching credentials; no escrow |
| `MEOS_SECRETS_KEY` | AI/TOTP secrets unreadable | re-enter AI keys; re-enroll MFA; E2E data unaffected |
| MCP admin password | cannot approve clients | rotate env, restart gateway; existing OAuth clients unaffected until revoked |
| App-managed MCP token (client side) | that client gets 401 | revoke it in the app and create a replacement; the old hash cannot be reversed |
| age identity/backup passphrase | that backup unreadable | another backup copy; no server escrow |
| Device | Keychain DEK gone | re-derive on another device with passphrase/recovery |

## 8. Non-goals / open items

- Argon2id on-device is not implemented; PBKDF2 600k is used. A vetted Swift Argon2id dependency plus a
  versioned KDF migration is the next improvement.
- Automatic production DEK rotation is not implemented; it remains a backup-gated offline procedure.
- Passkeys/WebAuthn are not implemented; TOTP is the second factor.
- The MCP host holds the vault passphrase/DEK while running; host compromise is vault compromise.

See `ENCRYPTION.md` for primitive details, `SECURITY.md` for the threat model, and
`docs/BACKUP.md` for the restore procedure.
