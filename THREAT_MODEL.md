# MeOS threat model

The detailed model — assets, boundaries, STRIDE, attack trees and residual-risk statement — is in
[`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md). This file is the short version used for reviews.

## Assets

1. Vault plaintext: finance ledger, notes/journals, health/fitness, events, chat, memory, documents and
   media.
2. Vault passphrase, recovery code, DEK.
3. Login password, session cookie, MFA seed/recovery codes.
4. AI provider keys and MCP OAuth grants.
5. Backups and audit logs.
6. Availability and integrity of the ledger (a wrong balance is a security failure too).

## Trust boundaries

| Boundary | Crossing | Control |
|---|---|---|
| App ↔ Worker | cookie, ciphertext, public vault meta | TLS, HttpOnly/SameSite cookie, Origin checks, rate limits |
| App ↔ Keychain | DEK | ThisDeviceOnly, device unlock |
| Worker ↔ D1/R2 | ciphertext + metadata | private binding, no public DB/R2 URL |
| Worker ↔ AI provider | prompt/context | user key encrypted; provider receives prompt by design |
| Gateway ↔ MeOS API | login session + ciphertext | HTTPS, normal user session, no DB credential |
| Gateway ↔ AI client | decrypted tool results | OAuth scopes, consent, audit, confirmation, revocation |
| Owner ↔ gateway | vault passphrase/admin password | local process, 0600 env, loopback |

## Primary attackers and controls

| Attacker | Attempt | Control |
|---|---|---|
| Anonymous | read private data | auth on every route; 401; MCP 401 |
| Credential stuffer | guess password | PBKDF2/Argon2id + pepper, 10/15min, MFA, generic errors |
| Session thief | replay cookie | hash-only DB, 30d/14d, revoke, explicit password re-auth for sensitive actions |
| DB-only | recover plaintext | client-side E2E ciphertext; server secrets need env key |
| R2-only | read files | ciphertext, private bucket, 10-min signed URLs |
| Other user | IDOR | `user_id` scoping on every query, media prefixes, tests |
| Malicious MCP client | exceed grant | per-module scopes, filtered tools, confirm, idempotency, rate limit, revocation |
| Prompt injection | authorize an export/delete | server checks scopes/ownership independent of model; untrusted content marker |
| Malicious AI provider | see more | explicit consent, minimum fields, no bulk export, disconnect |
| Gateway host compromise | steal passphrase/DEK | host is trusted; disk encryption, 0600, loopback, no untrusted code |
| Supply chain | malicious dependency | lockfiles, production audits, Semgrep/secret scan/Trivy CI |
| Insider/Cloudflare | read/delete | E2E content hidden; metadata visible; audit + backups |
| Physical device | read vault | OS encryption, Keychain ThisDeviceOnly, passphrase, biometric lock |

## Explicit non-guarantees

- A compromised unlocked client device can read what is on it.
- A compromised MCP host can read the vault while running.
- An AI provider processes plaintext it is given; E2EE ends at the tool response.
- A weak vault passphrase can be guessed offline from `meos.crypto`.
- D1 has no RLS; a missed `user_id` predicate is a code bug.
- No system is immune to zero-days, insider action, physical coercion or social engineering.

## Residual-risk statement

The largest risks are operational, not cryptographic: weak passphrase, compromised device/gateway,
human approval of the wrong MCP client/scope, and AI-provider exposure. They are documented in
`SECURITY.md` §12 and `SECURITY_AUDIT.md`; none is presented as eliminated.
