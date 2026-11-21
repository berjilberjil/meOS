# Backup and recovery

MeOS has three recovery layers. The detailed operator procedure is in
[`docs/BACKUP.md`](docs/BACKUP.md); this file is the executive record and test evidence.

## 1. Layers

| Layer | What it protects | Encryption | Where |
|---|---|---|---|
| D1 Time Travel | accidental delete/bad migration | Cloudflare-managed | same Cloudflare account, 30 days (plan-dependent) |
| Offsite D1 export | account/region loss, ransomware | `age` recipient | external/offline storage, via `scripts/backup-d1.sh` |
| Native encrypted JSON export | portability, vault/module copy | PBKDF2-600k + AES-256-GCM | user-chosen passphrase, via Settings or `scripts/decrypt-export.mjs` |
| R2 copy | event/body media | media is already client-sealed ciphertext | `rclone`/S3 copy, encrypt the copy |

A D1 backup contains `app_state` ciphertext, `meos.crypto` wrapped-key metadata, hashed sessions,
encrypted AI/TOTP secrets, devices and audit metadata. It does **not** contain the vault passphrase, the
plaintext DEK or R2 media.

## 2. Isolated restore drill (actually run)

`scripts/restore-drill.ts` creates synthetic data only, builds a D1-shaped SQLite database, seals a note
and a media object with the real MeOS vault format, takes a `VACUUM INTO` backup, restores it into a fresh
database, unlocks with the synthetic passphrase, decrypts the note/media, and tampers with ciphertext to
prove it is rejected.

Result (2026-11-21):

```json
{
  "ok": true,
  "database": "D1-shaped SQLite backup restored",
  "stateRows": 2,
  "vaultUnlocked": true,
  "noteDecrypted": true,
  "tamperRejected": true,
  "mediaDecrypted": true
}
```

Run it yourself:

```bash
cd mcp/meos
npm run test:restore
npm run test:rotate
```

`test:rotate` proves passphrase re-wrap, recovery re-wrap, old-credential rejection, existing ciphertext
preservation and a new-DEK re-encryption drill on synthetic data.

`./scripts/record-backup.sh backup age-d1` records a successful offsite backup in D1 so the Security
dashboard can show it. Run it only after verifying the encrypted file.

## 3. Recovery sequence

1. Stop clients and the MCP gateway; do not write during restore.
2. Restore D1 from Time Travel or an age-decrypted export into a fresh database.
3. Verify `users`, `app_state` row count, `meos.crypto` presence and one module decrypt locally.
4. Restore R2 objects if needed; they are ciphertext, so keep the key layout.
5. Re-enable one device, unlock with the passphrase/recovery code matching that backup.
6. Re-enable MCP clients with minimum scopes; run `./scripts/security-scan.sh`.
7. Record the restore with `scripts/record-backup.sh restore <label>`.

## 4. Key-loss statements

- **Passphrase lost, recovery code available**: unlock with recovery, set a new passphrase and a new code.
- **Passphrase + recovery lost**: encrypted modules are unrecoverable. There is no server escrow. A backup
  is useful only with the matching passphrase/recovery code.
- **Login password lost**: use an existing signed-in device/session; there is no email reset.
- **`MEOS_SECRETS_KEY` lost**: AI/TOTP secrets are unreadable; re-enter/re-enroll. E2E data is unaffected.
- **Backup passphrase/age identity lost**: that backup is unreadable; use another copy.

## 5. Retention and testing

- Suggested offsite retention: 14 daily, 8 weekly, 12 monthly; at least one offline copy.
- Test a restore at least quarterly and after any schema migration.
- Keep backup credentials separate from the backup files.
- Do not overwrite production while testing; use a separate D1/local SQLite copy.

## 6. Residual risk

- A backup is a full ciphertext + metadata copy; theft is still a confidentiality event, mitigated by age
  encryption.
- A compromised `age` identity or backup passphrase exposes the backup.
- R2 media is not in the D1 export; a full restore requires a separate media copy.
- A production DEK rotation is not automated; see `KEY_MANAGEMENT.md`.
