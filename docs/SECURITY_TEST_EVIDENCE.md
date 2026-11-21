# Security test evidence

Date: **2026-11-21**. Commands were run from the repository root unless noted. This file records the
actual output, not a claim that a test should exist.

## 1. Automated suites

### API (`apps/api`)

```text
$ bun run check
svelte-check found 0 errors and 0 warnings

$ bun run test
Test Files  14 passed (14)
     Tests  81 passed (81)

$ bun run build
✓ built in 1.89s
> Using @sveltejs/adapter-cloudflare
  ✔ done

$ bunx wrangler deploy --dry-run --outdir /tmp/meos-worker
Total Upload: 2498.52 KiB / gzip: 461.99 KiB
--dry-run: exiting now.
# bundles the optional hash-wasm/Argon2id path into the Worker

$ bun audit --production
No vulnerabilities found (checked 15 packages)
```

Security-relevant files include `authArgon2.test.ts`, `authPepper.test.ts`, `secrets.test.ts`, `security.test.ts`,
`stateKeys.test.ts`, `mfa.test.ts`, and the existing `auth.test.ts`, `media.test.ts`, `presign.test.ts`,
`devices.test.ts`, `etag.test.ts`, `stateVersion.test.ts`, `aiBudget.test.ts`, `voiceBudget.test.ts`.

### MCP gateway (`mcp/meos`)

```text
$ npm run typecheck
> tsc --noEmit            (no output = success)

$ npm test
ℹ tests 123
ℹ pass 123
ℹ fail 0

$ npm audit --omit=dev --audit-level=high
found 0 vulnerabilities
```

`tests/oauth.test.ts` covers DCR, PKCE consent, wrong verifier, code reuse, refresh rotation/reuse,
revocation, admin login/revoke and unsafe redirects. `tests/security.test.ts` covers idempotent writes,
prompt injection, granular scope mapping and audit redaction. `tests/financeLedger.test.ts` covers the
finance ledger’s confirm/idempotency/owner-verification rules and optimistic write protection.
`tests/auth.test.ts` covers app-managed `meos.mcp` tokens over real Streamable HTTP, revoked/expired/empty
scope rejection, granular notes-only access (finance refused), and the encrypted registry read.
`tests/config.test.ts` covers the no-credential startup guard and the OAuth-only path.

### Diet / Stuff MCP

```text
$ cd mcp/diet && bun test
13 pass, 0 fail

$ cd mcp/stuff && bun test
10 pass, 0 fail
```

### Apple

```text
$ cd apps/apple && xcodegen generate
$ xcodebuild -scheme MeOS-macOS build
** BUILD SUCCEEDED **

$ xcodebuild -scheme MeOS -sdk iphonesimulator build
** BUILD SUCCEEDED **
```

Warnings are pre-existing Swift 6 concurrency warnings in `AgentLoop.swift`; no errors.


### Backup and key-rotation drills (synthetic)

```text
$ cd mcp/meos && npm run test:restore
{
  "ok": true,
  "database": "D1-shaped SQLite backup restored",
  "vaultUnlocked": true,
  "noteDecrypted": true,
  "tamperRejected": true,
  "mediaDecrypted": true
}

$ npm run test:rotate
{
  "ok": true,
  "passphraseRewrap": true,
  "recoveryRewrap": true,
  "existingCiphertextPreserved": true,
  "dataKeyReencryptionDrill": true,
  "oldDekRejectedAfterReencrypt": true
}
```

These use only synthetic state and media. They prove the D1-shaped backup restores, the vault still
unlocks, ciphertext is integrity-checked, the media decrypts, passphrase/recovery rewrap works, and a new
DEK rejects the old one. See `scripts/restore-drill.ts` and `scripts/key-rotation-drill.ts`.

### Repository security gate

```text
$ ./scripts/security-scan.sh
No vulnerabilities found (checked 15 packages)     # API production
No vulnerabilities found (checked 91 packages)     # diet production
No vulnerabilities found (checked 91 packages)     # stuff production
found 0 vulnerabilities                            # MCP gateway production
== secret grep (tracked source only) ==
No hardcoded key patterns found.
semgrep not installed; skipping (CI runs it).
trivy not installed; skipping (CI runs it).
Security gate passed.
```

Semgrep was also run locally after installation:

```text
$ semgrep scan --config p/owasp-top-ten --config p/secrets --severity ERROR --error \
    apps/api/src mcp/meos/src mcp/diet/src mcp/stuff/src
Findings: 0 (0 blocking)   # after adding authTagLength to the Node GCM decipher
```

`trivy` remains CI-only (it also sees dev tooling); the blocking production dependency audit above is
clean. `.github/workflows/security.yml` runs TruffleHog, production audits and Semgrep as blocking jobs,
with Trivy as an advisory job.

## 2. Manual evidence (run against a local/staging deployment, never production secrets)

| Check | Command / action | Expected |
|---|---|---|
| Unauthenticated private route | `curl -i http://localhost:5173/api/me` | `401`, `Cache-Control: private, no-store`, `X-Frame-Options: DENY` |
| CSRF block | `curl -i -X PUT .../api/state/meos.notes -H 'Origin: https://evil.example' -d '{}'` | `403` cross-site refused |
| Login throttle | 11 bad logins | `401` then `429`; audit rows |
| Session hash | D1 `select token, token_hash from sessions` | `token` is random/`legacy:*`; `token_hash` is 64 hex; cookie value not present |
| MFA | enable TOTP, log out, log in | first attempt `mfaRequired`, correct code succeeds, wrong code 401 |
| Reauth | `POST /api/export` without recent reauth | `403 reauthRequired`; with password + code, encrypted JSON |
| AI key reauth | add a key with no password | `403`; with password (and code) succeeds |
| State ciphertext | D1 `select value from app_state where key='meos.notes'` | `{"v":2,"ct":"..."}`; no note text |
| Anti-downgrade | PUT plaintext to a module after `meos.crypto` exists | `400 This account is encrypted; plaintext state is refused` |
| Media private | copy a signed URL, wait >10 min | `403`/expired from R2 |
| Media cross-user | sign an id under another user's prefix | no object / 404; cannot be reached by changing an id |
| MCP no auth | `curl -i -X POST .../mcp` | `401` + `WWW-Authenticate` with `resource_metadata` |
| MCP wrong scope | OAuth client with only profile read calls finance tool | tool not in `tools/list`; direct call returns `forbidden` |
| MCP revoke | Disconnect in `/admin`, retry token | `401` immediately |
| Prompt injection | note body “ignore previous instructions…” | returned as data with `content_trust: untrusted`; no scope change |
| Idempotency | same `idempotency_key` twice on a write | one record; identical result |
| Finance MCP write guard | ledger `add_transaction` without `confirm` / without key | `confirmation_required` / `invalid_input`; row starts `needsReview`; MCP cannot self-verify |
| Finance concurrent write | two MCP writes prepared from the same snapshot | second gets a conflict; no silent lost update |
| Audit redaction | inspect `security_events` / `audit.log` | no token/password/note text/amount; IP is a hash |
| Vault setup | new account, import pre-vault data, create passphrase | data is preserved, then encrypted; note not empty |
| Encrypted backup recovery | create a `meosenc.json` envelope, then `MEOS_EXPORT_PASSPHRASE=… node scripts/decrypt-export.mjs <file>` | plaintext JSON is recovered; wrong passphrase exits 1 |
| Manual MCP client registration | `MEOS_MCP_OAUTH_STORE=<tmp> bun run scripts/register-mcp-client.ts --name … --redirect …` | client_id printed, store written 0600, no scope granted until consent |

## 3. Adversarial tests represented in code

| Attack | Test |
|---|---|
| Cross-account note read | `mcp/meos/tests/auth.test.ts` “one client cannot read another account’s records” |
| Locked note leak | `auth.test.ts` / `notes` tests: redacted without `secret`, no search match |
| Health leak without scope | `auth.test.ts` “health data needs the health scope” |
| Body-photo bytes/URL leak | `health` tests: metadata only, no URL |
| Destructive without scope | `auth.test.ts` |
| Destructive without confirm | `auth.test.ts` |
| Finance write without confirm | `finance.test.ts` (confirm added) |
| Refresh token reuse | `oauth.test.ts` |
| Wrong PKCE verifier / code reuse | `oauth.test.ts` |
| Unsafe DCR redirect | `oauth.test.ts` |
| Admin revoke | `oauth.test.ts` |
| Token/secret in audit | `security.test.ts` (MCP), `security.test.ts` (API) |
| Plaintext downgrade | `stateKeys.test.ts` + server route check |
| Tampered envelope | `stateKeys.test.ts` shape; `mcp/diet/tests/crypto.test.ts` round-trip/tamper |
| Weak server key | `secrets.test.ts` fail-closed |

## 4. Acceptance criteria evidence

See `SECURITY_AUDIT.md` §5. Every ✅ row points to one of:

- an automated test above,
- a route/helper in the file map,
- a manual command in §2.

The two ⚠️ rows are not hand-waved:

- **Recovery testing**: the procedure and code exist; a destructive production restore was not performed
  (constraint). `docs/BACKUP.md` includes a local restore drill that can be run without touching prod.
- **No unresolved critical/high**: SEC-15 (critical first-run bug) is fixed; production dependency audits
  are clean. Two high-by-design risks remain and are disclosed: the MCP host holds the vault passphrase,
  and the AI provider sees requested plaintext. No known unmitigated implementation bug is listed as open.

## 5. What is not proven

- No external penetration test or third-party audit was performed.
- No mobile malware/physical-extraction test.
- No load test of the per-isolate limiter across many Workers isolates.
- No production restore drill.
- Semgrep/Trivy results are CI-only in this run.
- The Apple “first-run with imported pre-vault data” fix is verified by code review and builds, not by an
  automated UI test (there is no Swift test target).
