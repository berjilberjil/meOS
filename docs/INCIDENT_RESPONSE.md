# Incident response

Single-owner project. This is a practical runbook, not a corporate IR plan. Preserve evidence before you
delete or rotate anything that you may need to understand what happened.

## 1. Severity

| Level | Example | Response |
|---|---|---|
| **Critical** | Vault passphrase/DEK exposed; database + env compromised; attacker decrypting E2E data | Immediate containment, offline forensics, assume all E2E data exposed, rotate everything, restore/verify |
| **High** | Session stolen; MCP client over-granted; AI provider key leaked; admin password guessed | Contain within hours, revoke, rotate, review audit |
| **Medium** | Repeated failed logins; leaked signed media URL; misconfigured CORS/headers | Fix within days, review exposure |
| **Low** | Scanner noise; dev-only dependency advisory; expired token | Track, patch in normal cycle |

## 2. First 15 minutes

1. **Do not wipe.** Export `/api/security/events`, the MCP `audit.log`, Cloudflare logs, and relevant D1
   rows (metadata only) to an encrypted local file.
2. **Contain sessions**: from an existing trusted device, re-auth and
   `DELETE /api/security/sessions` (revokes all other sessions). If the current session may be the
   compromised one, change the password first, which revokes others.
3. **Contain AI access**: open `http://127.0.0.1:8788/admin` (SSH-forward if remote) and **Disconnect** the
   suspect client. Stop the tunnel (`cloudflared tunnel run` process) if the host may be compromised.
4. **Contain infrastructure**: if Cloudflare credentials may be exposed, roll the API token and enable/
   reset 2FA; if the Worker is believed compromised, disable the route or deploy a known-good build.
5. **Preserve the vault**: do not attempt to "clean" `app_state`; ciphertext is evidence and may be needed
   for restore.

## 3. Assess

Answer:

- Which credential was exposed: login password, session, vault passphrase, DEK, AI key, MCP token, admin
  password, Cloudflare token?
- Which data classes could the attacker read? Remember: a session alone reads ciphertext, not E2E content.
- Which device/host was involved? Is it still running/online?
- What is the time window? Correlate audit `at`, MCP `ts`, Cloudflare request logs.
- Did the attacker modify data? Compare D1 `state_version`, module sizes, `updated_at`; check trash.
- Were backups accessed? Check storage access logs.

## 4. Eradicate and rotate

Do these in order, recording each action:

1. **Login password**: change it (current + new; MFA code if enabled). This revokes other sessions.
2. **Vault passphrase + recovery code**: unlock, change passphrase, generate a new recovery code, destroy
   old copies. This re-wraps the DEK. It does **not** re-encrypt old ciphertext already copied.
3. **AI provider keys**: delete/re-add each key; revoke the old key at the provider. Rotate the server
   `MEOS_SECRETS_KEY`: add new key, switch active, deploy, `POST /api/security/rotate-ai-keys`, remove old.
4. **MCP**: change `MEOS_MCP_ADMIN_PASSWORD`; disconnect every client; rotate/remove static tokens; restart
   the gateway; review `audit.log` for unexpected tools.
5. **Cloudflare**: rotate API tokens, R2 keys, tunnel credentials; review account members; enable 2FA.
6. **Devices**: sign out lost devices; if a device is lost and unlocked, assume vault exposure.
7. **Backups**: verify the latest backup predates the compromise or was not accessed. If in doubt, create a
   fresh backup from known-good state before rotating the vault, but label it “pre-rotation”.

## 5. Recover

- Restore from the newest verified encrypted backup; test decrypt before promotion (see `BACKUP.md`).
- Re-enable MCP clients one at a time with minimum scopes; verify `tools/list` only shows the intended
  modules.
- Re-run `scripts/security-scan.sh`, `bun run check/test/build`, MCP tests.
- Monitor `/api/security/events` and `/admin` for a week.

## 6. Notify

There is one owner and no customer data. If the exposure includes third-party provider keys, follow the
provider's compromise process (revoke key, check usage/billing). If a real person's data is involved
beyond the owner, follow applicable law; do not publish exploit details before the fix.

## 7. Post-incident

Write a short blameless note:

- timeline (UTC),
- root cause,
- data/credential exposure,
- what contained it,
- what would have detected it sooner,
- one or two concrete changes (test, header, scope default, rotation).

Add a regression test where possible. Update `SECURITY_AUDIT.md` and this runbook.

## 8. Specific playbooks

### Stolen session cookie
- Change password (revokes other sessions) → re-auth → revoke specific session if still listed.
- Review `state_write`, `ai_key_*`, `export`, `media_*`, `session_revoke` audit rows for the window.
- A session cannot decrypt E2E data; it can download ciphertext and replace `meos.crypto` (lockout).
- If `meos.crypto` was replaced, restore it from a backup before the change; otherwise the old DEK wrap is
  lost. Do not generate a new vault over the old ciphertext.

### Leaked MCP access token
- `POST /oauth/revoke` with the token, or Disconnect the client in `/admin`.
- Refresh tokens rotate; reuse already revokes the family.
- Rotate the client registration if the redirect URI was tampered with.

### Leaked vault passphrase
- Change passphrase and recovery code immediately.
- Assume any ciphertext copied before rotation remains decryptable with the old passphrase. There is no
  way to make an attacker forget it. A full DEK rotation/re-encrypt is required to invalidate old copies;
  that is currently a manual/offline procedure (SEC-22).

### MCP host compromise
- Stop the gateway/tunnel, revoke all OAuth clients, rotate the vault passphrase and recovery code, rotate
  MeOS login password, rotate AI keys/secrets, rebuild the host from a clean image.
- The attacker may have had the DEK while the vault was unlocked; treat E2E data as exposed.

### Lost device
- Revoke sessions, change password, rotate vault passphrase/recovery code. The Keychain DEK is
  `ThisDeviceOnly`; a locked device still needs the passphrase.
- If the device was unlocked and unattended, assume vault exposure.
