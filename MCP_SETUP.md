# Connecting MeOS to ChatGPT (and other AI clients)

MeOS exposes its real modules through the MCP gateway in [`mcp/meos`](mcp/meos). The gateway runs on a
machine **you control**, decrypts the vault there, and is reached by ChatGPT over an HTTPS tunnel.

This is deliberate:

- The MeOS backend stores ciphertext and never receives the vault passphrase or DEK.
- The gateway is the only process that holds plaintext, and only while it is running.
- ChatGPT receives only the results of the tools you authorize. It is a third-party processor; MeOS
  cannot make it unsee data it was asked to read.

If you want the convenience of "ask ChatGPT about my MeOS data", this is the architecture that keeps the
database provider out of the plaintext path.

There are two ways to connect a client:

| Client | Recommended auth | Where |
|---|---|---|
| Claude Desktop, OpenCode, Cursor, any client that accepts a remote URL + bearer header | **App-managed token** | MeOS → Settings → **MCP & AI connectors** |
| ChatGPT remote connector / any OAuth 2.1 client | **OAuth + PKCE** | consent screen with `MEOS_MCP_ADMIN_PASSWORD` |

Both use the same module scopes. App-managed tokens are created on an unlocked device, stored as a SHA-256
hash in the encrypted `meos.mcp` document, and shown raw only once. The gateway decrypts that document with
the vault passphrase; revoke a token in the app and it is refused on the next registry refresh (10 seconds).
The gateway must therefore have `MEOS_VAULT_PASSPHRASE` (or `MEOS_VAULT_RECOVERY`) even when it uses
app-managed tokens.

---

## 1. What you need

- A Mac (or Linux host) that stays awake enough for the assistant to reach it.
- Node.js **22.18+** (Node 24/26 recommended).
- A domain or subdomain, e.g. `mcp.example.com`.
- `cloudflared` (or Caddy/nginx with a public TLS certificate).
- Your MeOS login, vault passphrase (or recovery code), and a password manager.

The gateway signs in to MeOS with server-side credentials. Those credentials and the vault passphrase
are never sent to ChatGPT and are not accepted as tool arguments.

---

## 2. Install and configure the gateway

```bash
cd mcp/meos
npm install
cp .env.example .env
chmod 600 .env
```

Fill in at minimum:

```dotenv
MEOS_BASE_URL=https://meos-api.berjiljacob.workers.dev
MEOS_USERNAME=your-meos-username
MEOS_PASSWORD=your-meos-login-password
MEOS_VAULT_PASSPHRASE=your-vault-passphrase
# Only if you enabled TOTP MFA on the MeOS login:
# MEOS_MFA_SECRET=<the base32 seed shown once during MFA setup>

MEOS_MCP_TRANSPORT=http
MEOS_MCP_HTTP_HOST=127.0.0.1
MEOS_MCP_HTTP_PORT=8788
MEOS_MCP_HTTP_PATH=/mcp

MEOS_MCP_PUBLIC_URL=https://mcp.example.com
MEOS_MCP_ADMIN_PASSWORD=<openssl rand -base64 24>
MEOS_MCP_ALLOW_DCR=true
MEOS_MCP_ADMIN_LOCAL_ONLY=true

MEOS_MCP_SCOPES=read          # only relevant to stdio / static tokens
MEOS_MCP_RATE_LIMIT=120
MEOS_MCP_LOG_LEVEL=info
```

Generate the admin password with `openssl rand -base64 24`. It is **not** your MeOS login or vault
passphrase; it only approves OAuth clients and unlocks `/admin`.

Start it:

```bash
npm start
```

You should see `ready` on stderr and `GET http://127.0.0.1:8788/healthz` should return
`{"ok":true,"service":"meos-mcp","oauth":true}`.

### Desktop connector with an app-managed token

1. Keep `MEOS_VAULT_PASSPHRASE` set and leave `MEOS_MCP_HTTP_TOKEN` blank.
2. Start the gateway (`npm run start:http`).
3. In MeOS → **Settings → MCP & AI connectors**, save the local URL
   `http://127.0.0.1:8788/mcp` (or your public HTTPS URL) and tap **Test gateway**.
4. **Create MCP token**, pick only the modules the client needs (profile read is the default), and copy the
   generated config or URL + `Authorization: Bearer …` header into the client.
5. Revoke the connector in the app when you are done. The gateway refuses it within 10 seconds.

The raw token is shown once. MeOS stores only its SHA-256 hash; losing the token means creating a new one,
not recovering the old one.

### Keep the secrets off the process list

`node --env-file` reads the file; it does not put the values in `ps`. Keep `.env` at mode `600` and owned
by your user. For a persistent install, a LaunchAgent is preferable to a terminal window:

```xml
<!-- ~/Library/LaunchAgents/com.berjil.meos.mcp.plist -->
<key>ProgramArguments</key>
<array>
  <string>/usr/bin/env</string>
  <string>node</string>
  <string>--env-file-if-exists=/Users/you/meOS/mcp/meos/.env</string>
  <string>/Users/you/meOS/mcp/meos/src/index.ts</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
```

Do not commit `.env`. The root `.gitignore` already ignores it.

---

## 3. Put it behind HTTPS

### Cloudflare Tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create meos-mcp
cloudflared tunnel route dns meos-mcp mcp.example.com
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: meos-mcp
credentials-file: /Users/you/.cloudflared/<tunnel-id>.json
ingress:
  # Admin is local-only anyway; refuse it at the edge as a second layer.
  - hostname: mcp.example.com
    path: ^/admin
    service: http_status:404
  - hostname: mcp.example.com
    service: http://127.0.0.1:8788
  - service: http_status:404
```

```bash
cloudflared tunnel run meos-mcp
```

The public surface is:

| Path | Purpose | Public? |
|---|---|---|
| `/mcp` | Streamable HTTP MCP endpoint | yes, Bearer required |
| `/.well-known/oauth-*` | OAuth discovery | yes, metadata only |
| `/oauth/register` | Dynamic client registration | yes, rate-limited |
| `/oauth/authorize` | Owner consent | yes, admin password required |
| `/oauth/token`, `/oauth/revoke` | Token exchange/revocation | yes |
| `/admin` | Client dashboard | **no** (loopback only by default) |
| `/healthz` | Liveness | yes, no data |

If you use Caddy instead, terminate TLS and `reverse_proxy 127.0.0.1:8788`. Never expose port 8788
directly.

---

## 4. Connect ChatGPT

ChatGPT's custom MCP connector support is plan/rollout dependent. In a workspace that has **Developer
mode / custom connectors**:

1. Open **Settings → Connectors → Advanced → Developer mode** (wording varies).
2. Choose **Add custom connector**.
3. Name: `MeOS`.
4. URL: `https://mcp.example.com/mcp`.
5. Leave authentication as OAuth / "Discover". ChatGPT calls
   `https://mcp.example.com/.well-known/oauth-protected-resource`, registers itself through
   `/oauth/register`, and opens the consent page.
6. On the consent page:
   - Tick the modules you actually want this assistant to read. The default is **only profile**.
   - Add write scopes only if you want ChatGPT to change MeOS.
   - Leave `secret` and `destructive` off unless you understand the consequence.
   - Enter the `MEOS_MCP_ADMIN_PASSWORD` and press **Allow selected**.
7. Back in ChatGPT, the connector should show as connected and its tools should appear.

If the connector cannot discover OAuth, confirm the public URL is reachable from the internet and that
`MEOS_MCP_PUBLIC_URL` exactly matches the origin you typed (scheme + host, no path).

### First questions to try

- "Using MeOS, what did I spend this month, and how does it compare with last month?"
- "Give me a daily briefing from my MeOS tasks, events, fitness and finance. Only use what you can read."
- "What habits have I missed this week?"
- "Summarize my notes tagged with the project name X." *(MeOS has no tags; search by text instead.)*
- "What is my current emergency fund / net-worth position?" *(Fold must be linked.)*

The model must call a tool for each module. It cannot query the database directly; there is no SQL tool.

---

## 5. What ChatGPT can and cannot see

MeOS is end-to-end encrypted. The gateway decrypts on your machine and returns **only the fields the
authorized tool returns**. There is no bulk export tool and no "read everything" tool.

| Your data | ChatGPT can see it if… |
|---|---|
| Profile, goals, achievements | `meos.profile.read` |
| Finance snapshot / purchases / encrypted ledger | `meos.finance.read` |
| Weight, calories, steps | `meos.health.read` |
| Workouts, programme | `meos.fitness.read` |
| Notes | `meos.notes.read`; locked note bodies also need `secret` |
| Tasks, habits | `meos.tasks.read` |
| Events, reminders | `meos.calendar.read` |
| Memory bank | `meos.memory.read` |
| Diet plan/log | `meos.diet.read` |
| Learning log | `meos.knowledge.read` |
| Media metadata / trash | `meos.files.read`; body-photo metadata also needs `secret` |
| Aggregates/status | `meos.analytics.read` |

Not available at all: raw media bytes, encryption keys, password hashes, session tokens, database
credentials, arbitrary SQL, arbitrary URLs, shell access, money transfers, credential changes.

See [`docs/AI_PERMISSION_MATRIX.md`](docs/AI_PERMISSION_MATRIX.md) for the tool-by-tool matrix.

---

## 6. Managing and revoking clients

Open the dashboard on the gateway host:

```bash
open http://127.0.0.1:8788/admin
# remote host:
ssh -L 8788:127.0.0.1:8788 you@host
```

It shows each client's name, id, redirect URI, granted scopes, live token counts, creation/last-use
times and recent tool calls (metadata only). **Disconnect** revokes every access token, refresh token and
authorization code for that client immediately. ChatGPT's next request gets `401` and must re-authorize.

To revoke from the command line, remove the client from the dashboard; there is no public revoke-all
endpoint. Token revocation for a single token is `POST /oauth/revoke` (RFC 7009).

Rotating `MEOS_MCP_ADMIN_PASSWORD` invalidates future logins but does not revoke existing OAuth clients;
disconnect them in the dashboard.

---

## 7. Other clients

### Claude Desktop / Claude Code (stdio)

Use [`mcp.json.example`](mcp/meos/mcp.json.example). stdio is a local pipe; the OS process boundary is the
authentication boundary. Keep `MEOS_MCP_SCOPES=read` unless you deliberately want writes.

### Cursor / remote HTTP with a static token

```json
{
  "mcpServers": {
    "meos": {
      "url": "https://mcp.example.com/mcp",
      "headers": { "Authorization": "Bearer ${env:MEOS_MCP_HTTP_TOKEN}" }
    }
  }
}
```

Static tokens do not expire unless you set `expires_at` in `MEOS_MCP_CLIENTS_JSON`; prefer OAuth for
anything long-lived.

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `401` and no consent page | Check `MEOS_MCP_PUBLIC_URL` exactly matches the URL; check the tunnel routes `/.well-known/*` and `/oauth/*`. |
| `Unknown client` | The client registration was lost or revoked. Remove/re-add the connector so it registers again. If it cannot use DCR, register manually: `bun scripts/register-mcp-client.ts --name "…" --redirect "https://…/callback"`. |
| Consent page 403 "Admin is local-only" | You opened `/admin` through the tunnel. Use localhost or SSH forwarding, or set `MEOS_MCP_ADMIN_LOCAL_ONLY=false` deliberately. |
| `invalid_grant` on token exchange | Code expired (5 min), already used, redirect URI changed, or PKCE verifier mismatch. Start the connection again. |
| `invalid_target` | The client requested a different `resource` than `MEOS_MCP_PUBLIC_URL` + path. Fix the connector URL. |
| Tools missing | The client lacks that module scope. Re-authorize and tick it; `tools/list` is filtered by design. |
| `vault_locked` | `MEOS_VAULT_PASSPHRASE` / `MEOS_VAULT_RECOVERY` is missing or wrong. The login password does not unlock the vault. |
| `confirmation_required` | Destructive or finance write without `confirm: true`; money-moving ledger writes also need a unique `idempotency_key`. Ask the assistant to confirm the action with you first. |
| ChatGPT times out | The gateway host is asleep/offline or the tunnel is down. Check `/healthz` and the dashboard's last-use time. |
| Everything is read-only | That is the default. Grant a write scope on the consent screen, deliberately. |

---

## 9. Security rules for this setup

1. The gateway process holds the vault passphrase. Treat the host as a trusted device: disk encryption,
   screen lock, no shared account, `.env` mode 600. If MFA is enabled, it also holds the TOTP seed
   (`MEOS_MCP_MFA_SECRET`); that is required for unattended sign-in and is another reason the host must be
   trusted.
2. The consent page and admin password cross the HTTPS tunnel; Cloudflare terminates TLS at its edge.
   Treat the tunnel provider as part of your trust boundary, or use a tunnel/VPN you control. The gateway
   itself only listens on loopback.
3. The tunnel exposes only the MCP/OAuth paths. Keep `/admin` local.
4. Grant the smallest scope set. A client with `meos.notes.read` cannot read finance, and `tools/list`
   will not advertise finance.
5. Re-authorize after changing scopes; old tokens keep their old grant until revoked/expired.
6. Disconnect clients you no longer use. Refresh tokens live 30 days.
7. Do not paste the vault passphrase or admin password into ChatGPT. The consent page is served by the
   gateway, not by the model.
8. The AI provider sees the plaintext you ask it to retrieve. Do not grant `secret`/health/finance to a
   provider you would not trust with that data.
