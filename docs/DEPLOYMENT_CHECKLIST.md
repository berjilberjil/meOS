# Deployment checklist

Use this before and after every production deploy. Do not deploy with a critical/high unmitigated finding.

## 1. Pre-flight (local)

```bash
cd apps/api
bun install --frozen-lockfile
bun run check
bun run test
bun run build

cd ../../mcp/meos
npm ci
npm run typecheck
npm test

cd ../diet && bun test
cd ../stuff && bun test

cd ../.. && ./scripts/security-scan.sh
cd apps/apple && xcodegen generate && xcodebuild -scheme MeOS-macOS build && xcodebuild -scheme MeOS -sdk iphonesimulator build
```

- [ ] All suites pass.
- [ ] `scripts/security-scan.sh` passes (production audits + secret grep).
- [ ] No `.env`, `.dev.vars`, key, token or personal data staged (`git status`).
- [ ] Commit identity is the personal one (`berjilberjil`), not work.

## 2. Secrets / configuration

- [ ] `MEOS_SECRETS_KEY` is 32 random bytes, base64 (`openssl rand -base64 32`), or a key ring.
- [ ] `MEOS_PASSWORD_PEPPER` is set to a **separate** stable value.
- [ ] `MEOS_MFA_RECOVERY_PEPPER` is set (independent of the password pepper).
- [ ] `MEOS_AUDIT_SALT` is set.
- [ ] `R2_*` credentials are scoped to the media bucket; no account-wide token.
- [ ] `MEOS_ALLOW_SIGNUP` unset after the first account.
- [ ] `MEOS_SETUP_TOKEN` set for the first deploy (send `setupToken` with the first
      registration), then kept or removed deliberately.
- [ ] `MEOS_CORS_ORIGINS` / `MEOS_TRUSTED_ORIGINS` empty unless a browser client exists.
- [ ] `GEMINI_*` keys are server-only; no key in the app bundle.
- [ ] MCP: `MEOS_MCP_PUBLIC_URL` matches the tunnel origin; `MEOS_MCP_ADMIN_PASSWORD` is random and ≥12;
      `.env` mode 600; `MEOS_MCP_ADMIN_LOCAL_ONLY=true`.

## 3. Database

- [ ] Take a backup (`./scripts/backup-d1.sh`) and verify it decrypts.
- [ ] Apply **additive** DDL only (`db/schema.sqlite.sql` changes) after a backup.
- [ ] No destructive migration (drop/rename/delete) without a reviewed plan and a restore rehearsal.
- [ ] `sessions`/`security_events`/`user_mfa` tables exist; `sessions.token_hash` is indexed.
- [ ] Confirm one `app_state` value is `{v,ct}` for a sealed module; confirm `meos.crypto` exists.

## 4. Deploy the Worker

```bash
cd apps/api
bun run build
bunx wrangler deploy
```

- [ ] `wrangler deploy` succeeded.
- [ ] `curl -i https://<host>/api/me` → 401, `Cache-Control: private, no-store`, `X-Frame-Options: DENY`,
      `X-Content-Type-Options: nosniff`, HSTS.
- [ ] `curl -i -X PUT https://<host>/api/state/meos.notes -H 'Origin: https://evil.example'` → 403.
- [ ] Login works; wrong password is generic 401; repeated failures are 429.
- [ ] TOTP setup (if used) returns a secret once; login with code works.
- [ ] State sync works on Mac and iPhone; a note written on one appears on the other.
- [ ] Media upload/download works; a signed URL expires after ~10 minutes.
- [ ] `/api/security/sessions` lists devices; revoke-others works after reauth.
- [ ] `/api/security/events` shows the login/state events (no payloads).

## 5. Deploy the MCP gateway

- [ ] `npm ci && npm run typecheck && npm test`.
- [ ] `MEOS_MCP_TRANSPORT=http`, loopback bind, tunnel only to `/mcp` + OAuth paths.
- [ ] `/healthz` returns `oauth: true`.
- [ ] `.well-known/oauth-protected-resource` and `oauth-authorization-server` return the public origin.
- [ ] Register a test client, consent with only `meos.profile.read`; `tools/list` has no finance/health.
- [ ] Disconnect in `/admin`; the next call is 401.
- [ ] `audit.log` is 0600 and contains tool names but no args.
- [ ] Restart the gateway; OAuth clients still work (persistent store) or require re-auth (expected).

## 6. Post-deploy monitoring (first 24 h)

- [ ] `/api/security/events`: failed logins, CSRF blocks, new sessions, exports, key changes.
- [ ] MCP `/admin`: unexpected clients/scopes/tools.
- [ ] Cloudflare: 5xx rate, CPU, D1 rows read, R2 egress.
- [ ] No secret in logs (`wrangler tail` sampled; redaction holds).
- [ ] Backups scheduled and stored offsite.

## 7. Rollback

- Worker: deploy the previous known-good commit; the additive DB columns are backward-compatible.
- Vault: do **not** roll back `meos.crypto` unless you intend to roll back the passphrase; restoring an
  older meta may make current ciphertext unreadable if the DEK changed. The DEK does not change on
  passphrase rewrap, but a full restore should be tested.
- MCP: stop the process; revoke clients; restore the previous `oauth.json` only if you accept the token
  state in it.
- If a deploy introduced a security regression, disable the route/feature first, then fix; do not leave a
  permissive fallback in place.

## 8. Sign-off

| Check | Owner | Date |
|---|---|---|
| Tests + security scan | | |
| Backup verified | | |
| Worker smoke tests | | |
| MCP OAuth + revoke | | |
| No new high/critical finding | | |
