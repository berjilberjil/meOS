# Incident response

The full runbook is [`docs/INCIDENT_RESPONSE.md`](docs/INCIDENT_RESPONSE.md). This is the one-page version.

## 1. First actions

1. Stop writes: put devices offline, stop the MCP gateway, stop the tunnel if the host may be compromised.
2. Preserve evidence: export `/api/security/events`, the MCP `audit.log`, Cloudflare logs and relevant
   D1 metadata to an encrypted local file. Do not wipe the vault.
3. Contain sessions: change the login password (revokes other sessions) or, from a trusted device,
   re-auth and `DELETE /api/security/sessions`.
4. Contain AI: `/admin` → Disconnect the suspect OAuth client; stop the gateway/tunnel.
5. Contain infrastructure: roll Cloudflare API/R2/tunnel credentials if they may be exposed; enable 2FA.

## 2. Assess

- Which credential: login password, session, vault passphrase/DEK, AI key, MCP token/admin password,
  Cloudflare token?
- Which data classes could be read? A session alone reads ciphertext; a vault passphrase/DEK reads C4.
- Which device/host and time window? Correlate audit `at`, MCP `ts`, Cloudflare logs.
- Was data modified? Check `state_version`, finance audit entries, trash and `updated_at`.
- Were backups accessed? Check storage logs and backup status.

## 3. Eradicate / rotate

1. Change login password; re-auth with MFA.
2. Change vault passphrase and recovery code (re-wraps DEK); if DEK/passphrase was exposed, assume old
   ciphertext copies remain readable until a full DEK re-encryption.
3. Delete/re-add AI provider keys; rotate `MEOS_SECRETS_KEY` (add key → activate → rotate endpoint → retire
   old key); re-enroll MFA if its seed was exposed.
4. Rotate `MEOS_MCP_ADMIN_PASSWORD`; disconnect all MCP clients; rotate/remove static tokens; restart the
   gateway; review `audit.log`.
5. Rotate Cloudflare/R2/tunnel credentials; review account members; enable 2FA.
6. Revoke lost devices/sessions.

## 4. Recover

- Restore from a verified encrypted backup; test a local decrypt first (`docs/BACKUP.md`).
- Re-enable one device, then MCP clients with minimum scopes.
- Run `./scripts/security-scan.sh`, API/MCP tests, and `npm run test:restore` / `test:rotate`.
- Record the restore with `scripts/record-backup.sh restore <label>`.
- Monitor the Security screen and `/admin` for a week.

## 5. Notify / learn

There is one owner and no customer data. If a provider key is exposed, follow that provider's compromise
process. Write a short blameless timeline, root cause, exposure, containment and one or two concrete
changes; add a regression test where possible.

## 6. Playbooks

- **Stolen session**: change password, revoke sessions, review `state_write`/`ai_key_*`/`export`/`media_*`
  events. A session cannot decrypt E2E data but can replace `meos.crypto` (lockout). Restore meta from
  backup if that happened.
- **Leaked MCP token**: `POST /oauth/revoke` or Disconnect; refresh reuse already revokes the family.
- **Leaked vault passphrase**: rotate passphrase + recovery code; old ciphertext copies remain readable
  until DEK re-encryption.
- **MCP host compromise**: stop gateway/tunnel, revoke all clients, rotate vault + login + AI keys, rebuild
  host; assume vault exposed while unlocked.
- **Lost device**: revoke sessions, rotate passphrase/recovery; Keychain DEK is device-only.
