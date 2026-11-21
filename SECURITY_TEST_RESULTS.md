# MeOS security test results

Date: **2026-11-21**
Branch: `feat/security-hardening` (based on `main` including the finance OS + finance MCP ledger)
Synthetic data only; no production deployment or destructive migration was performed.

## 1. Automated results

| Suite | Result | Evidence |
|---|---|---|
| API type-check | 0 errors / 0 warnings | `bun run check` |
| API unit tests | **82 passed / 82** (14 files) | `bun run test` |
| API production build | success | `bun run build` + `wrangler deploy --dry-run` (2.50 MB / 462 KB gzip) |
| API production deps | **0 vulnerabilities** | `bun audit --production` (15 packages) |
| MCP gateway type-check | clean | `npm run typecheck` |
| MCP gateway tests | **123 passed / 123** | `npm test` |
| MCP production deps | **0 vulnerabilities** | `npm audit --omit=dev --audit-level=high` |
| Diet MCP | 13 passed | `bun test` |
| Stuff MCP | 10 passed | `bun test` |
| Semgrep OWASP + secrets | **0 findings** | local + CI |
| Secret grep | clean | `scripts/security-scan.sh` |
| Apple macOS build | **BUILD SUCCEEDED** | `xcodebuild -scheme MeOS-macOS` |
| Apple iOS simulator build | **BUILD SUCCEEDED** | `xcodebuild -scheme MeOS -sdk iphonesimulator` |
| Backup restore drill | **passed** | `npm run test:restore` |
| Key-rotation drill | **passed** | `npm run test:rotate` |

The exact command output is in [`docs/SECURITY_TEST_EVIDENCE.md`](docs/SECURITY_TEST_EVIDENCE.md).

## 2. What the tests actually prove

### Authentication / sessions
- PBKDF2 v2/v3/v4 and legacy scrypt verification, peppered v3 round-trip, optional Argon2id v4 round-trip,
  no downgrade of v4 to v3, wrong password rejected.
- TOTP RFC 6238 vector, ±30s skew, recovery-code normalization.
- Session hashing, expiry/idle, revoke-one/revoke-others, password/MFA session revocation (API audit code +
  route tests where present).
- Login/MFA/re-auth throttles share the D1 login-attempt window.

### API / database isolation
- State-key allowlist, encrypted-envelope and vault-meta structural validation, plaintext downgrade refusal.
- Origin/CSRF/CORS/header tests, audit redaction, salted IP hashing, burst limiter.
- Every API query is reviewed for `user_id`; no endpoint accepts a client-supplied user id.
- Finance ledger read-modify-write now checks `updatedAt` against a forced-fresh read.

### Encryption
- AES-256-GCM v1/v2 envelope round-trip; v2 per-key HKDF; wrong key/AAD/tampered ciphertext rejected.
- Server secret key ring: v2 ciphertext, legacy decrypt, weak-key fail-closed, rotation.
- Synthetic backup restore: D1-shaped SQLite restore + vault unlock + note/media decrypt + tamper rejection.
- Synthetic rotation: passphrase/recovery rewrap, old credentials rejected, existing ciphertext preserved,
  new-DEK re-encryption rejects the old DEK.

### MCP / AI
- OAuth DCR, PKCE consent, wrong verifier, code reuse, refresh rotation/reuse, revocation, admin
  login/revoke, unsafe redirect rejection.
- Granular scopes, filtered `tools/list`, direct ungranted call denied, cross-account isolation,
  locked-note/private-profile redaction.
- App-managed tokens (`Settings → MCP & AI connectors`) authenticate from the encrypted `meos.mcp` registry;
  revoked, expired, unparsable and empty-scope tokens fail closed; a notes-only token cannot read finance.
  The raw token is never stored or returned by the server.
- Prompt-injected note content cannot widen scopes or auto-confirm a destructive action.
- Finance ledger writes require `confirm: true` + a unique idempotency key; AI rows start `needsReview`;
  MCP cannot mark them verified/reconciled.
- No SQL, shell, filesystem or arbitrary URL tool.

### Storage / frontend
- Media IDs reject traversal; upload caps; signed URLs 600s; private R2 assumption; body/event media sealed.
- Apple ATS is on with only localhost exceptions; build succeeds.
- CSP/HSTS/frame/nosniff/referrer/COOP/CORP headers; no third-party scripts in the API HTML surface.
- No secrets in frontend bundles; secret grep + CI TruffleHog.

## 3. Manual / environment checks not fully automated

| Item | Status |
|---|---|
| Production D1 Time Travel restore | Not run; would need Cloudflare account access and explicit approval |
| Cloudflare R2 bucket public access check | Not run against production; bucket must be private by configuration |
| External penetration test | **Not performed**; this is the main reason the score is not 9–10 |
| OWASP ZAP dynamic scan | Not run; Semgrep/Trivy/secret scan + targeted tests only |
| Real iPhone device build/signing | Simulator build only |
| Push-notification/device-specific behavior | Not security-tested |

## 4. Acceptance criteria

| Criterion | Status | Evidence |
|---|---|---|
| No unauthenticated private data | ✅ | API/MCP 401 tests; route review |
| No cross-user access | ✅ | scoped queries; MCP two-account tests |
| No public private storage | ✅ (config + code) | private R2, 600s signed URLs; production bucket audit still manual |
| No plaintext master keys on backend | ✅ | `meos.crypto` wrapped only; server secret key ring |
| Sensitive data client-side encrypted | ✅ | envelopes + media sealing + D1 inspection procedure |
| Encryption integrity verified | ✅ | tamper tests + restore drill |
| Key rotation verified | ✅ partial | passphrase/recovery + server key ring + synthetic DEK drill; production DEK rotation is manual |
| Secure recovery verified | ✅ synthetic | restore drill; production restore not run |
| Password hashing modern | ✅ partial | optional Argon2id v4; PBKDF2 v3 default; on-device vault still PBKDF2 600k |
| MFA / session revocation | ✅ | TOTP + route + session API |
| Database authorization | ✅ | app-level `user_id`; no RLS (documented) |
| API authorization | ✅ | scope/ownership checks + tests |
| No secrets in frontend bundles | ✅ | build + secret scan |
| No sensitive logs | ✅ | audit/log redaction tests |
| MCP OAuth validated | ✅ | OAuth tests |
| MCP per-tool permissions | ✅ | scope map + tests |
| Revoked AI clients blocked | ✅ | admin revoke test |
| Prompt injection cannot bypass auth | ✅ | injection test + server checks |
| Sensitive AI writes require confirmation | ✅ | finance/destructive confirm tests |
| No unrestricted SQL/shell/filesystem | ✅ | tool inventory review |
| Backup restore tested | ✅ synthetic | `test:restore` |
| Security regression tests pass | ✅ | 82 API + 123 MCP + diet/stuff |
| No unresolved critical | ✅ | SEC-15 fixed; no known open critical |
| No unresolved high without acceptance | ⚠️ | disclosed high-by-design: MCP host trust, AI-provider plaintext |
| Independent penetration test | ❌ | not performed |

## 5. Honest score

**8 / 10 — advanced security implementation.**

Why not 9–10:

- No independent third-party penetration test.
- No production backup restore drill.
- Vault passphrase KDF is still PBKDF2 600k, not Argon2id; on-device Argon2id needs a vetted library and a
  versioned migration.
- No passkeys/WebAuthn.
- No automated production DEK rotation.
- MCP gateway host compromise still means vault compromise while running.
- AI providers see plaintext returned by tools; that is outside the E2EE boundary.
- D1 has no RLS; isolation depends on code review/tests.
- Dev-only tooling advisories remain in Vite/Vitest/Wrangler.

Why 8 rather than lower: genuine client-side E2EE, real OAuth/scopes/revocation, tested prompt-injection
and finance-write controls, hash-only sessions, MFA, re-auth, audit trail, encrypted restore drill, clean
production dependency audits and CI security gates.

## 6. Commands

```bash
cd apps/api && bun run check && bun run test && bun run build && bun audit --production
cd mcp/meos && npm ci && npm run typecheck && npm test && npm run test:restore && npm run test:rotate
cd mcp/diet && bun test
cd mcp/stuff && bun test
cd ../.. && ./scripts/security-scan.sh
cd apps/apple && xcodegen generate && xcodebuild -scheme MeOS-macOS build && xcodebuild -scheme MeOS -sdk iphonesimulator build
```
