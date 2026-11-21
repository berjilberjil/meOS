# Backup and recovery

MeOS has two backup layers: Cloudflare D1 Time Travel (short-term, same account) and encrypted offsite
exports (long-term, independent). R2 media is separate and must be copied explicitly.

## 1. What a backup contains

| Layer | Contents | Sensitive? |
|---|---|---|
| D1 | users, hashed sessions, ciphertext `app_state`, encrypted AI/TOTP secrets, devices, audit metadata | **yes** — treat as a secret |
| R2 | event/body media ciphertext | yes (ciphertext + object names) |
| Export JSON | `app_state` ciphertext + `meos.crypto` + masked AI keys + device metadata + media counts | yes |

A D1 backup restores module data and the wrapped DEK. It does **not** contain the vault passphrase or the
DEK in plaintext, and it does **not** contain R2 objects. A restore without the passphrase/recovery code is
unreadable; that is intentional.

## 2. D1 Time Travel

Cloudflare keeps 30 days of D1 point-in-time recovery on paid plans (check your plan). This is the fastest
way to recover from a bad migration or accidental delete.

```bash
# Find a timestamp/bookmark
wrangler d1 time-travel info meos --remote

# Restore (example; confirm the timestamp first)
wrangler d1 time-travel restore meos --timestamp 2026-11-20T10:00:00Z --remote
```

Time Travel lives in the same Cloudflare account. If the account is compromised or the database is
deleted, it is not an independent backup. Keep offsite exports.

## 3. Encrypted offsite export

```bash
# one-time: create an age identity
age-keygen -o ~/.config/meos/backup.agekey
chmod 600 ~/.config/meos/backup.agekey
# public key is printed; store it in a password manager
export AGE_RECIPIENT=age1...

./scripts/backup-d1.sh ./backups
```

The script:

1. `wrangler d1 export meos --remote --output <plain>.sql`
2. `age -r $AGE_RECIPIENT` encrypts it
3. deletes the plaintext SQL
4. leaves a 0600 `.sql.age` file

Move the `.age` file off the machine (external drive, object storage with its own credentials, paper key
in a safe). Do not upload the age **private** key with the backup.

Verify a backup without restoring:

```bash
age -d -i ~/.config/meos/backup.agekey backups/meos-d1-*.sql.age | head
age -d -i ~/.config/meos/backup.agekey backups/meos-d1-*.sql.age | sha256sum
```

## 4. Native encrypted JSON export

Settings → **Export encrypted backup** creates `MeOS-backup.meosenc.json`:

```json
{
  "format": "meos-encrypted-export",
  "version": 1,
  "kdf": "pbkdf2-sha256",
  "iterations": 600000,
  "salt": "base64",
  "ct": "base64(nonce‖ciphertext‖tag)",
  "createdAt": "ISO-8601"
}
```

It contains the same module JSON the app shows, sealed under a **backup passphrase** you choose (separate
from the vault passphrase if you prefer). The file is sealed before it touches disk; the app removes
temporary copies on logout.

Decrypt it locally with the included tool:

```bash
MEOS_EXPORT_PASSPHRASE='your backup passphrase' \
  node scripts/decrypt-export.mjs MeOS-backup.meosenc.json > restored.json
```

The result is plaintext — handle it as you would the vault, and delete it after import. The native app does
not yet have a one-click "restore this JSON" UI; a restore is a deliberate import into a running app or a
fresh database. The file is a portability/recovery copy, not a live sync source.

## 5. R2 media

Media is ciphertext, but it is still personal data and is not in the D1 export. Options:

```bash
# rclone with an R2 remote configured
rclone copy r2:meos-media ./backups/r2-media --progress
```

Then encrypt the directory with age/tar before moving it offsite. Keep the object key layout
(`event-media/<user>/…`, `body-photos/<user>/…`) so a restore can put objects back.

## 6. Restore procedure (tested locally, not in production)

1. **Stop writes**: put the app in airplane mode / stop the MCP gateway. Do not let clients push while you
   restore.
2. **Create a fresh local D1** and import:
   ```bash
   wrangler d1 create meos-restore
   wrangler d1 execute meos-restore --local --file=backups/restored.sql
   ```
3. **Verify**:
   ```sql
   select count(*) from users;
   select count(*) from app_state;
   select key, length(value) from app_state order by key;
   select substr(value,1,40) from app_state where key='meos.crypto';
   ```
   Confirm `meos.crypto` exists and the expected module keys are present. Do not print full values into
   shared logs.
4. **Point a dev Worker** at the restored D1, sign in, unlock with the passphrase, and open a note/event.
   A successful decrypt proves the wrapped DEK and ciphertext survived.
5. **Promote** only after the check: use Time Travel/import into the production database during a
   maintenance window, or re-deploy with the restored binding.
6. **Re-enable** clients and the gateway. Revoke OAuth clients if the restore is from before a compromise.

If the restore is from a backup older than the current `meos.crypto`, the passphrase may differ. Use the
passphrase/recovery code that matches that backup; do not overwrite a newer vault meta with an older one
unless you intend to roll back.

## 7. Retention

- D1 Time Travel: 30 days (plan dependent).
- Offsite exports: daily for 14 days, weekly for 8 weeks, monthly for 12 months (suggested). Keep at least
  one copy offline.
- R2: mirror the same schedule, or rely on R2 versioning if enabled.
- Audit logs: 180 days in D1, 5 MB × 3 rotations in the MCP gateway.
- Delete expired backups securely (crypto-shred the age file and its key if retiring).

## 8. Key-loss scenarios

| Lost | Result | Recovery |
|---|---|---|
| Login password | Cannot sign in | Existing device/session, or operator reset (no email reset) |
| Vault passphrase, recovery code available | Vault locked | Unlock with code, set a new passphrase |
| Vault passphrase + recovery code | E2E data unrecoverable | Restore a backup **and** find the matching passphrase/code; no escrow |
| `MEOS_SECRETS_KEY` | AI/TOTP secrets unreadable | Re-enter AI keys; re-enroll MFA; E2E data unaffected |
| Cloudflare account | Infrastructure lost | Recreate Worker/D1/R2, restore export, re-point DNS; E2E data safe if backup/passphrase safe |
| MCP admin password | Cannot approve clients | Rotate it in env and restart the gateway; existing OAuth clients keep working until revoked |

## 9. What not to do

- Do not store the age private key next to the backups.
- Do not upload a plaintext SQL export to cloud storage.
- Do not test a restore by overwriting production.
- Do not assume a database backup includes R2 photos.
- Do not promise recovery if the passphrase and recovery code are both lost; the cryptography does not
  allow it.
