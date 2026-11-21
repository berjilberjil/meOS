# MeOS encryption

This document describes what is actually implemented, what it protects, and what it does not. It is
written to be checked against the code, not to sound impressive.

Primary code:

- `apps/apple/MeOS/Core/Crypto/MyOSCrypto.swift` — primitives
- `apps/apple/MeOS/Core/Crypto/Vault.swift` — key hierarchy, envelopes, recovery
- `apps/apple/MeOS/Core/Crypto/KeychainStore.swift` — device key storage
- `apps/api/src/lib/server/secrets.ts` — server-side AES-GCM for AI/TOTP secrets
- `mcp/diet/src/crypto.ts` — the same vault format in the MCP/Node runtime
- `apps/api/src/lib/server/stateKeys.ts` — envelope/meta shape checks, anti-downgrade

---

## 1. Threat model

**Protected against**

- A database dump, backup theft or read-only SQL access: `app_state` and R2 media are ciphertext.
- A Cloudflare/R2 operator reading module contents: they hold bytes, not the DEK.
- A compromised Worker: it can read the server-held AI/TOTP secrets only if `MEOS_SECRETS_KEY` is also
  compromised; it still cannot read E2E module data.
- Ciphertext tampering or moving a blob between state keys: AES-GCM authentication + AAD / per-key HKDF.
- A stolen session trying to downgrade a module to plaintext: the client drops plaintext when a vault
  exists, and the server refuses to store it (anti-downgrade).

**Not protected against**

- A compromised *client device* while the vault is unlocked. The DEK is in memory and the data is on
  screen. Malware with the user's privileges can read it.
- A weak vault passphrase. The wrapped DEK is stored in `meos.crypto`; an attacker with that file can
  brute-force the passphrase offline. PBKDF2 600k raises the cost but does not make a weak passphrase safe.
- A compromised MCP gateway host. It holds the passphrase in its environment and the DEK in memory.
- The AI provider after data is returned to it. That is a deliberate disclosure, not a break.
- Metadata: counts, sizes, times, device names, module names, audit events.
- A malicious client that controls the plaintext before encryption (it can write anything it wants into
  its own vault; MeOS cannot validate truthfulness).

---

## 2. Key hierarchy

```
vault passphrase ──PBKDF2-SHA256(600,000, passSalt)──▶ KEK_pass ──AES-256-GCM──▶ wrappedByPass
recovery code   ──PBKDF2-SHA256(600,000, recoverySalt)▶ KEK_rec  ──AES-256-GCM──▶ wrappedByRecovery

random 32-byte DEK ────────────────────────────────────┐
                                                       ├── data envelope v1: AES-GCM(DEK, AAD=state key)
                                                       └── data envelope v2: HKDF(DEK, "meos.data.v2:<key>")
                                                                              └─ AES-GCM(subkey, AAD="meos.envelope.v2:<key>")
```

- The **DEK** is generated with `SecRandomCopyBytes` (32 bytes), never sent to the server, and cached in
  the macOS/iOS Keychain as `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `meos.crypto` stores only: format version, KDF name, iterations, salts, the two wrapped DEK copies, a
  fixed check token sealed under the DEK, and (new vaults) `dataVersion: 2`. It does **not** store the DEK
  or the passphrase.
- The server stores `meos.crypto` verbatim; it cannot unwrap anything.

### Why PBKDF2 and not Argon2id

CryptoKit/CommonCrypto on the app's deployment targets do not provide Argon2id. A hand-rolled Argon2id
would be a custom cryptographic implementation, which is worse than a standard KDF. The app therefore uses
PBKDF2-HMAC-SHA256 at **600,000** iterations (above the OWASP 2023 floor) with a 16-byte random salt. This
is an honest gap versus the ideal; moving to Argon2id requires a vetted library and a versioned KDF
migration, not a quick change. `CryptoMeta.kdf` is checked by the client and the entry point rejects
unknown KDFs.

The server login password is a separate credential. It uses PBKDF2 (peppered `v3` when
`MEOS_PASSWORD_PEPPER` is set) because the Worker free tier caps CPU at 10 ms/request. The vault passphrase
is the one that protects the data, and it never reaches the server.

---

## 3. Envelope formats

### State value

```json
{ "v": 2, "ct": "base64(nonce‖ciphertext‖tag)" }
```

- v1 (legacy, and existing vaults): key = DEK; AAD = the exact state key string (e.g. `meos.notes`).
- v2 (new vaults): key = HKDF-SHA256(DEK, info=`meos.data.v2:<state key>`); AAD =
  `meos.envelope.v2:<state key>`.
- Nonce: 96-bit random per encryption by CryptoKit/WebCrypto. No nonce is reused with the same key.
- Tag: 128-bit GCM tag. Decryption fails closed on any tag/AAD mismatch.
- The server validates the envelope shape (`v` 1–10, base64 `ct` ≥ 28 bytes) and stores it verbatim.

v2 is additive and opt-in by vault age: a vault created by this build has `dataVersion: 2`; an existing
vault keeps `dataVersion` absent and continues to write v1 so older installed clients can still read it.
Both clients read both versions. A future migration can re-seal an existing vault under v2; until then,
the v2 benefit applies to new vaults only.

Compatibility note: an **older app build** cannot open a new v2 vault. Existing vaults are unaffected
(they remain on v1), so update every device before creating a brand-new vault if you still run a build
from before this change.

### Vault metadata

```json
{
  "v": 1,
  "kdf": "pbkdf2-sha256",
  "iterations": 600000,
  "passSalt": "base64(16)",
  "recoverySalt": "base64(16)",
  "wrappedByPass": "base64(nonce‖ct‖tag)",
  "wrappedByRecovery": "base64(nonce‖ct‖tag)",
  "check": "base64(nonce‖ct‖tag)",
  "dataVersion": 2
}
```

AADs: `wrap:pass`, `wrap:recovery`, `check`. The check token is the fixed bytes
`myos.vault.check.v1`; a candidate DEK is only accepted if it opens `check` to exactly that value.

### File/media envelopes

- Event media: `MyOSCrypto.seal(bytes, DEK, AAD="event-media:<id>")` (`EventMediaStore.aad`).
- Body/progress photos: `MyOSCrypto.seal(bytes, DEK, AAD="body-photo:<id>")` (`ProgressPhotoSync.aad`).
- Fold tokens: sealed under the DEK with a domain-separated AAD, stored in the Keychain / encrypted module.
- The server stores opaque bytes in R2 and never signs a URL to an MCP client.
- Encrypted backup: `EncryptedExport.Envelope` with PBKDF2 600k over a user-chosen backup passphrase,
  AES-GCM with AAD `meos.export.v1`. The file is sealed before it reaches the temporary directory.

---

## 4. Guarantees

| Property | Implementation |
|---|---|
| Confidentiality at rest | AES-256-GCM; DEK never leaves the client |
| Integrity | GCM tag; AAD binds ciphertext to its state key / media id |
| Key separation | Per-key HKDF subkeys in v2; AAD domain separation in v1 |
| Nonce uniqueness | 96-bit random per encryption, generated by the platform CSPRNG |
| Key isolation between users | Each account has its own DEK/salts; `user_id` scoping is separate |
| Tamper rejection | GCM authentication; decryption throws, no partial plaintext |
| Server cannot decrypt | No DEK/passphrase in the Worker or D1; only wrapped copies |
| Recovery | One-time recovery code re-wraps the same DEK; no escrow |
| Passphrase change | Re-wraps the DEK under a new KEK; ciphertext unchanged |
| Recovery rotation | Re-wraps the DEK under a new recovery code |
| Server secret encryption | AES-256-GCM key ring; versioned `v2:<key-id>:...`; legacy decrypt |
| Server secret rotation | Add key → activate → `/api/security/rotate-ai-keys` (AI + MFA) |

### Explicit non-guarantees

- Server-side AES-GCM for AI/TOTP secrets is **not** end-to-end encryption. The Worker can decrypt those
  values; it must, to call the provider/verify TOTP.
- The server can delete or corrupt ciphertext (availability/integrity of storage is not cryptographically
  prevented). Backups are the mitigation.
- The server can observe access patterns and sizes.
- The AI provider can retain/process whatever plaintext it receives.
- The MCP gateway can read the vault while running. It is a trusted endpoint.

---

## 5. Recovery and key loss

- **Forgot vault passphrase, have recovery code**: unlock with the code, then set a new passphrase. The
  same DEK is re-wrapped; data is preserved.
- **Forgot both**: the wrapped DEK cannot be opened. The ciphertext is unrecoverable. There is no server
  escrow, no backdoor, and no "reset encryption" that keeps data.
- **Lost device**: the DEK is `ThisDeviceOnly`; sign in on another device with the passphrase/recovery code
  and it derives the same DEK from `meos.crypto`.
- **Stolen device, vault locked**: the Keychain item requires device unlock; the wrapped DEK still needs
  the passphrase. Sign out/revoke sessions and rotate the passphrase/recovery code.
- **Stolen device, vault unlocked**: assume the data was exposed. Rotate the passphrase and recovery code;
  this does not re-encrypt old ciphertext already copied by an attacker.

---

## 6. Rotation procedures

### Vault passphrase (implemented)

Settings → **Change encryption passphrase** asks for the current vault passphrase, the new one, and a
fresh login password (plus MFA code if enabled). The server sees the login re-auth, never the vault
passphrase; the client verifies the current passphrase and re-wraps the DEK.

1. Unlock the vault on a trusted device.
2. Enter the current passphrase (the client verifies it locally).
3. The client derives a new KEK with a new salt, re-wraps the **same** DEK, and uploads `meos.crypto`.
4. Other devices need the new passphrase on their next unlock. The DEK does not change, so ciphertext is
   untouched.
5. The recovery code is independent; rotate it separately if it may have been exposed.

### Recovery code (implemented)

1. Unlock the vault.
2. Generate a new code; the client re-wraps the DEK under a new recovery salt/KEK.
3. The old code stops working once the new `meos.crypto` is stored. Destroy the old paper copy.

### DEK / data-key rotation (not automated)

There is no one-click "re-encrypt everything" yet. A safe manual procedure would be: export, decrypt on a
trusted offline machine, create a new vault, import, verify, destroy the old ciphertext. This is a
follow-up because a partial rotation is worse than none. The envelope `v` field and `dataVersion` exist so
a migration can be written and tested without changing the wire format.

### Server secrets (implemented)

1. Generate a new 32-byte key: `openssl rand -base64 32`.
2. Add it to `MEOS_SECRETS_KEYS` as a new id; point `MEOS_SECRETS_KEY_ID` at it; deploy.
3. Keep the old key in the ring (it decrypts existing rows).
4. `POST /api/security/rotate-ai-keys` with a fresh re-auth; it re-encrypts AI credentials and the TOTP
   secret.
5. Verify; then remove the old key. Removing it before rotation makes those rows unreadable.
6. This does not change login password hashes or the vault DEK.

### Password pepper (manual)

`MEOS_PASSWORD_PEPPER` must stay stable. Changing it invalidates existing `v3` hashes. Existing `v2`/legacy
hashes still verify and are upgraded on the next login. If you must change it, keep the old value available
until every account has logged in, or implement a multi-pepper version.

---

## 7. What the database administrator sees

For a designated E2E module, a DBA sees:

```
key:        "meos.notes"
value:      {"v":2,"ct":"9c1f...base64..."}
updated_at: "2026-11-21T09:00:00.000Z"
```

They do not see note titles, bodies, amounts, events, health values, chat, or media bytes. They do see the
module names, row counts, sizes, timestamps, the public vault metadata (salts/wrapped keys), device names,
session metadata, audit metadata, and AI model routing. This is the documented metadata boundary.

---

## 8. Verification

- `apps/api/src/lib/server/secrets.test.ts` — v2 round-trip, key-ring decryption, weak-key fail-closed,
  legacy decrypt.
- `apps/api/src/lib/server/stateKeys.test.ts` — vault metadata shape, envelope shape, plaintext rejection.
- `mcp/diet/tests/crypto.test.ts` — vault round-trip and tamper behavior.
- MCP suites — sealed state, cross-account isolation, locked-note redaction.
- Apple builds — CryptoKit/CommonCrypto compile for macOS and iOS simulator; the first-run setup path
  decodes plaintext before adopting the new meta (regression test is manual).
- Manual: create a note, inspect D1 `app_state.value` and confirm it is `{v,ct}`; replace one base64 byte
  and confirm the client rejects it; open `meos.crypto` and confirm there is no raw key.

The acceptance criteria and command output are in
[`docs/SECURITY_TEST_EVIDENCE.md`](docs/SECURITY_TEST_EVIDENCE.md).
