# MeOS MCP gateway

One central [Model Context Protocol](https://modelcontextprotocol.io) server for MeOS. It exposes the
modules that genuinely exist in this repository to authorised AI clients over **stdio** or **Streamable
HTTP**, using the existing MeOS backend and the existing zero-knowledge vault.

This is an extension of MeOS, not a second product:

- No duplicate database, user table, or profile.
- No SQL tool and no service-role credential.
- Identity always comes from a verified MeOS session created from server-side credentials.
- The diet tools reuse the native diet logic in [`mcp/diet/src/plan.ts`](../diet/src/plan.ts); there is
  still exactly one meal-plan implementation.

---

## 1. What was actually audited

The repository has moved on from the Supabase/Postgres design described in some older files:

| Layer | Reality in this repo |
|---|---|
| Backend | `apps/api` — headless SvelteKit on Cloudflare Workers |
| Database | Cloudflare **D1** (SQLite), not Supabase Postgres |
| Data shape | One JSON document per module in `app_state` (`meos.notes`, `meos.events`, …) |
| Auth | Username/password → `meos_session` cookie (60 days), PBKDF2-SHA256 |
| Encryption | Client-side AES-256-GCM vault; `meos.crypto` holds the wrapped DEK |
| Media | Private Cloudflare R2, ciphertext only, short-lived signed GETs |
| Native apps | SwiftUI Mac + iPhone; all modules live in `apps/apple` |
| Existing MCP | `mcp/diet` (stdio) and `mcp/stuff` (stdio), both via a Mac loopback bridge |
| Supabase migrations | Historical design reference; not the live schema |

### What exists, and therefore what is exposed

| Module | Exposed | Deliberately not exposed (does not exist) |
|---|---|---|
| Finance | Encrypted transaction ledger, accounts, transfers, spending, budgets, goals, recurring, investments/valuations, liabilities, net worth history, timeline; separate Fold snapshot; Stuff purchases and ownership burn | Statement-import parser, live market prices, tax-liability calculation, year-sharded storage |
| Health | Daily weight/calories/protein/water/steps/note, 7/30-day averages, BMI, targets | Medical records, labs, medication |
| Fitness | Workout history/details, logging, exercise history, progress, custom exercises, active program | Seed exercise names (not synced), medical advice |
| Tasks | Per-day to-dos (text, done, planned minutes, focus seconds), daily habits | Priority, due dates, cross-day projects, task recurrence |
| Goals | Short/mid/long life-goal strings, achievements, fitness goal, archive-to-achievement | Goal percentages, deadlines, delete |
| Notes | Title/body, pin, lock, search, recycle bin; rich attachments preserved | Tags, folders, backlinks |
| Events | Events, tags, recurrence rules, reminder lead times, projected occurrences | Standalone reminder rows, external calendar sync |
| Memory | Curated durable facts, search, create/update | Delete (no recycle-bin kind exists) |
| Devices / system | Profile, device list, module presence, media usage, safe settings | Tokens, sessions, keys, password hashes |
| AI | Provider/model ids, masked keys, non-secret routing | Raw provider keys, system prompts, chat execution |
| Diet | Context, week plan, day log, food search, logging, custom foods, targets | — (reuses the native diet logic) |
| Learning | YouTube learning log + takeaways | — |

**Removed from MeOS:** the journal. Finance is now a first-class encrypted ledger in the native app.
`meos_finance_ledger_*` reads and writes that document through the same vault and state store as every
other module. `meos_finance_*` remains the separate Fold/Stuff surface. The two must never be mixed.
The statement-import parser and live market feed are still deliberately absent.

`meos_get_capabilities` returns this inventory at runtime so an agent can check instead of assuming.

---

## 2. Architecture

```
MCP client (Claude Desktop / Claude Code / Cursor / other)
        │  stdio  or  Streamable HTTP (POST /mcp + Bearer token)
        ▼
mcp/meos  ── auth ─ rate limit ─ scope check ─ zod validation ─ audit log
        │
        ├── MeosApiClient  ── HTTPS ──▶ apps/api (Cloudflare Worker)
        │                                  └── D1 app_state + R2
        │
        ├── VaultService   ── unlocks the DEK from meos.crypto, AES-GCM per key
        ├── StateStore     ── one key at a time, per-key lock, no whole-state writes
        └── existing diet/plan.ts for all meal maths
```

Every write touches **only the module key being changed** (plus `meos.trash` for deletes). There is no
endpoint that accepts arbitrary SQL, table names, or user ids.

```
mcp/meos/
  src/
    index.ts            entry point (stdio or HTTP)
    http.ts             Streamable HTTP transport, bearer auth, body cap
    server.ts           server construction + instructions
    auth/               scopes, bearer resolution, rate limiting
    config/             env parsing, client/account model
    services/           API client, vault, state store, logger
    tools/              finance, health, tasks, goals, notes, events, memory,
                        system, diet, knowledge
    resources/          read-only meos:// resources
    prompts/            reusable MeOS prompts
    schemas/            structural mirrors of the Swift models
    utils/              dates, pagination, recurrence, errors, result envelope
  tests/                fake MeOS backend + 91 tests
```

---

## 3. Install and run

Requirements: **Node.js ≥ 22.18** (the repo is tested on Node 26). No Bun is required for this gateway.

```bash
cd mcp/meos
npm install
cp .env.example .env
chmod 600 .env
# fill MEOS_USERNAME, MEOS_PASSWORD and either MEOS_VAULT_PASSPHRASE or MEOS_VAULT_RECOVERY
```

### stdio (local development and desktop clients)

```bash
npm run start:stdio
```

The process speaks MCP on stdout; all logs go to stderr. It is normally launched by the client, not by
hand.

### Streamable HTTP (remote clients)

```bash
MEOS_MCP_TRANSPORT=http \
MEOS_MCP_HTTP_TOKEN='generate-a-long-random-token' \
npm start
# POST http://127.0.0.1:8788/mcp
```

The HTTP transport is **stateless** (`enableJsonResponse: true`): every MCP request is a POST. Server-sent
GET streams are intentionally disabled (405). This keeps the gateway horizontally simple and avoids
long-lived in-memory sessions.

The listener refuses to start without a token, and refuses a non-loopback bind unless
`MEOS_MCP_ALLOW_REMOTE=true`. For any remote deployment, terminate TLS in a trusted proxy (Caddy, nginx,
Cloudflare Tunnel) and keep the gateway itself on loopback.

Health check: `GET /healthz` → `{"ok":true}` (no data, no auth).

---

## 4. Configuration

All configuration is server-side environment. Nothing in a tool call can widen permissions or choose a
user.

| Variable | Required | Meaning |
|---|---|---|
| `MEOS_MCP_TRANSPORT` | no | `stdio` (default) or `http` |
| `MEOS_BASE_URL` | no | Defaults to the hosted API; HTTPS unless localhost |
| `MEOS_USERNAME` / `MEOS_PASSWORD` | yes | MeOS account used by the server |
| `MEOS_VAULT_PASSPHRASE` | for encrypted data | Vault passphrase |
| `MEOS_VAULT_RECOVERY` | alternative | One-time recovery code |
| `MEOS_TIMEZONE` | no | IANA zone for "today" and app-style stamps; set when the host is elsewhere |
| `MEOS_MCP_SCOPES` | no | Scopes for stdio / single-token mode; default `read` |
| `MEOS_MCP_HTTP_TOKEN` | HTTP single-client | Bearer token |
| `MEOS_MCP_CLIENTS_JSON` | HTTP multi-client | Per-client token hash, scopes, account, optional expiry |
| `MEOS_MCP_ACCOUNTS_JSON` | no | Additional MeOS accounts for genuine isolation |
| `MEOS_MCP_HTTP_HOST` / `PORT` / `PATH` | no | Defaults `127.0.0.1:8788/mcp` |
| `MEOS_MCP_ALLOW_REMOTE` | no | Must be `true` to bind non-loopback |
| `MEOS_MCP_RATE_LIMIT` | no | Requests per client per minute (default 120) |
| `MEOS_MCP_MAX_BODY_BYTES` | no | HTTP body cap (default 2 MB) |
| `MEOS_MCP_LOG_LEVEL` | no | `debug`, `info`, `warn`, `error` |

Multi-client example (raw tokens are hashed at startup and discarded; `token_sha256` avoids plaintext
entirely):

```bash
MEOS_MCP_CLIENTS_JSON='[
  {"id":"claude-desktop","token":"TOKEN_ONE","scopes":["read"],"account":"owner","expires_at":"2027-01-01T00:00:00Z"},
  {"id":"cursor","token_sha256":"<64-hex-sha256>","scopes":["read","write","health"],"account":"owner"},
  {"id":"automation","token_sha256":"<64-hex-sha256>","scopes":["read","write","destructive"],"account":"owner"}
]'
```

Expired tokens are refused at the HTTP boundary. Rotate a token by replacing it in configuration and
restarting; revoke by removing it. (The MeOS login session itself is an implementation detail of the
gateway and never leaves it.)

---

## 5. Permission model

| Scope | Grants |
|---|---|
| `read` | list, get, search, analyse, summarise |
| `write` | create, update, complete, tick, log |
| `destructive` | delete/purge; **also requires `confirm: true` in the call** |
| `health` | health, fitness, diet and body-photo data (read and write) |
| `secret` | locked notes, profile contact/private brief, body-photo metadata |

Rules enforced in code:

1. A newly configured client is **read-only** unless scopes are granted.
2. Every tool declares its required scopes; all must be present.
3. Destructive tools additionally refuse without `confirm: true`, and the tool input schema includes it.
4. Reads of health/fitness/diet need `health`. Body-photo metadata needs `health` **and** `secret`.
5. Locked note bodies and profile private fields need `secret`; without it they are redacted, not missing.
6. The body-photo tools never return image bytes, thumbnails, or signed URLs.
7. Unauthorized calls are rejected before the handler runs, so they reveal nothing about the record.

Tested cases include: read-only client cannot write; write client cannot destruct; missing confirm is
refused; one account cannot read another's notes; expired token is refused.

---

## 6. Tool catalogue

116 tools are registered at runtime; `meos_get_capabilities` is the authoritative inventory.

All results use the same envelope:

```json
{
  "success": true,
  "data": {},
  "metadata": { "source": "MeOS", "retrieved_at": "2026-11-21T09:00:00.000Z" }
}
```

Errors are `{ "success": false, "error": { "code", "message", "hint?" } }` with `isError: true`.
Lists use `limit` (max 100) and an opaque `cursor`; the response includes
`page.next_cursor`, `page.has_more`, and `total_matching` where meaningful.

### Finance ledger (`read`, writes need `write`)

These tools read and write the encrypted `meos.finance` document. The gateway unlocks it with the same
vault DEK used for notes and health; it never reads plaintext from the server. Finance writes require the
`write` scope (`MEOS_MCP_SCOPES=read,write`). Destructive finance deletion is deliberately not exposed;
corrections use `update_transaction` with a mandatory audit reason.

| Tool | Purpose |
|---|---|
| `meos_finance_ledger_get_summary` | Net worth, assets, liabilities, cash, investments, month totals |
| `meos_finance_ledger_list_accounts` | Signed balances, available credit, reconciliation date |
| `meos_finance_ledger_list_transactions` | Filtered, paginated ledger with classification flags |
| `meos_finance_ledger_get_transaction` | One transaction plus its immutable audit trail |
| `meos_finance_ledger_search` | Search payee, note, reference, tag, category or account |
| `meos_finance_ledger_get_spending` | Category/payee spend and savings rate |
| `meos_finance_ledger_get_net_worth` | Dated net-worth history with certainty |
| `meos_finance_ledger_get_investments` | Holdings, invested capital, return, allocation |
| `meos_finance_ledger_get_liabilities` | Outstanding debt, EMI, rate, ownership |
| `meos_finance_ledger_list_budgets` | Planned vs actual and variance |
| `meos_finance_ledger_list_goals` | Goal targets and progress |
| `meos_finance_ledger_get_timeline` | First events and user milestones |
| `meos_finance_ledger_add_account` | Create an owned account |
| `meos_finance_ledger_add_transaction` | Record income, expense, refund, fee, tax, interest, dividend, investment or loan repayment |
| `meos_finance_ledger_update_transaction` | Correct a non-transfer row with required audit reason |
| `meos_finance_ledger_add_transfer` | Create a linked pair; never income/spend |
| `meos_finance_ledger_add_investment` | Add a holding and dated valuation |
| `meos_finance_ledger_add_valuation` | Upsert a dated valuation |
| `meos_finance_ledger_add_liability` | Add a loan/card liability |

### Fold snapshot + Stuff (`read`, writes need `write`)

| Tool | Purpose |
|---|---|
| `meos_finance_get_summary` | Fold net worth/cash/investments/debt/spend + Stuff burn |
| `meos_finance_list_accounts` | Masked bank accounts and balances |
| `meos_finance_get_net_worth` | Net worth exactly as Fold reports, plus components/history |
| `meos_finance_get_investments` | Investment totals; states holdings are unavailable |
| `meos_finance_get_spending` | Category spend with refunds/interest separated |
| `meos_finance_list_purchases` | Stuff ledger with ROI maths, filterable/paginated |
| `meos_finance_get_purchase` | One purchase |
| `meos_finance_add_purchase` | Log a purchase (rupees or `"₹2,499"`, months → 30-day life) |
| `meos_finance_update_purchase` | Partial update; `retired=true` preferred over delete |
| `meos_finance_delete_purchase` | Move to recycle bin (**destructive + confirm**) |
| `meos_finance_list_categories` | Built-in + custom Stuff shelves |
| `meos_finance_get_purchase_summary` | Ownership burn vs take-home pay |

**Financial accuracy:** the ledger tools use the same rules as the app. Transfers, card settlements and
investment purchases are not spending; refunds reduce spend; loan principal reduces debt and only
interest is an expense. The Fold tools pass Fold's numbers through unchanged and flag a snapshot older
than two days as stale. An unlinked Fold returns `linked: false`, not zero. Never sum Fold and ledger
figures into one number.

### Health and fitness (`read`/`write` + `health`)

`meos_health_get_summary`, `meos_health_list_daily_metrics`, `meos_health_get_daily_metrics`,
`meos_health_upsert_daily_metrics`, `meos_health_get_body_metrics`,
`meos_fitness_get_profile`, `meos_fitness_get_workout_history`, `meos_fitness_get_workout_details`,
`meos_fitness_log_workout`, `meos_fitness_update_workout`, `meos_fitness_get_exercise_history`,
`meos_fitness_get_progress`, `meos_fitness_list_body_photos` (+`secret`),
`meos_fitness_get_goals`, `meos_fitness_list_exercises`, `meos_fitness_get_program`.

Workout writes preserve the existing `ExerciseLog`/`SetLog` shape. `mode="merge"` appends; `"replace"`
overwrites that day's entries only. Averages and calorie targets are explicitly labelled as calculated
(Mifflin-St Jeor, same as the app). Body-photo metadata never includes a URL or bytes.

### Tasks and goals

`meos_tasks_list`, `meos_tasks_get`, `meos_tasks_create`, `meos_tasks_update`,
`meos_tasks_complete`, `meos_tasks_delete`, `meos_tasks_list_habits`,
`meos_tasks_set_habit`, `meos_tasks_summary`.
A task belongs to a date; moving one keeps its id and banked focus seconds. Deleting captures the task
and its day in `meos.trash`, and restore puts it back on that day.

`meos_goals_list`, `meos_goals_get`, `meos_goals_create`, `meos_goals_update`,
`meos_goals_archive`, `meos_goals_set_fitness`.
Goal refs are `short:0`, `mid:1`, `long:2`. Archive moves the text into the profile's achievements
timeline; there is no goal delete.

### Notes

`meos_notes_list`, `meos_notes_search`, `meos_notes_get`, `meos_notes_create`,
`meos_notes_update`, `meos_notes_pin`, `meos_notes_lock`, `meos_notes_delete`.

Search covers title and body text plus created/updated date filters. There is no tag model. A plain-text
body edit rebuilds paragraph blocks while carrying over image/link-card attachments, matching the app's
own `BlockDoc.merging`. Locked notes are redacted without `secret` (including their title in the bin).

### Events and reminders

`meos_events_list` (with optional recurrence expansion), `meos_events_get`, `meos_events_create`,
`meos_events_update`, `meos_events_delete`, `meos_events_get_upcoming`, `meos_events_list_tags`,
`meos_reminders_list`, `meos_reminders_set`.

Occurrences are projected from the stored rule, never duplicated. The month-day is clamped from the
anchor (31 Jan → 28/29 Feb → 31 Mar; 29 Feb returns on the next leap year). Updating an event without
passing `reminders` preserves its reminders exactly; `meos_reminders_set` changes only the named event.
The gateway never touches device notification schedules — the app rebuilds them from `meos.events`.

There is no standalone reminder record, so there is no fake `reminders_complete`.

### Memory

`meos_memory_list`, `meos_memory_search`, `meos_memory_get`, `meos_memory_create`,
`meos_memory_update`. Credentials/OTPs/card numbers are refused, and near-duplicates are rejected. Memory
delete is not exposed because MeOS has no recycle-bin kind for it.

### System, devices, AI and safety

`meos_get_profile`, `meos_get_app_status`, `meos_get_module_status`, `meos_get_storage_usage`,
`meos_list_devices`, `meos_get_device`, `meos_ai_get_available_models`, `meos_ai_get_routes`,
`meos_get_settings`, `meos_list_trash`, `meos_restore_from_trash`, `meos_purge_from_trash`,
`meos_get_capabilities`.

- Profile photo is never returned. Contact details and the private brief need `secret`.
- Storage usage is aggregate media only (count + bytes), with `health`; no filenames or dates.
- AI keys are masked as the backend stores them; routing is scrubbed of secret-looking fields.
- Trash listing omits payloads; restore handles every kind with a recyclable payload; purge is
  destructive + confirm and releases held R2 media keys.

### Diet (reuses `mcp/diet/src/plan.ts`)

`meos_diet_get_context`, `meos_diet_get_week_plan`, `meos_diet_get_day_log`,
`meos_diet_search_foods`, `meos_diet_list_recent_foods`, `meos_diet_set_meal_slot`,
`meos_diet_add_food_to_slot`, `meos_diet_remove_slot_food`, `meos_diet_clear_meal_slot`,
`meos_diet_clear_week_plan`, `meos_diet_log_food`, `meos_diet_log_planned_meal`,
`meos_diet_delete_log_item`, `meos_diet_upsert_food`, `meos_diet_set_goals`.

Weekday `0` = Sunday … `6` = Saturday. Planned-meal copy refuses an empty slot or an already-logged meal
instead of overwriting food that was actually eaten. Log deletion and full-plan clearing are destructive
+ confirm.

### Learning log

`meos_knowledge_list_videos`, `meos_knowledge_add_video`,
`meos_knowledge_update_video`, `meos_knowledge_delete_video`.

---

## 7. MCP resources

Resources are pull-based and use the same permission checks as their tools. Connecting a client does not
automatically read personal data.

| URI | Content |
|---|---|
| `meos://profile` | Profile (redacted without `secret`) |
| `meos://finance/ledger` | Encrypted ledger net worth/assets/liabilities summary |
| `meos://finance/ledger/spending` | Encrypted ledger current-month spending |
| `meos://finance/summary` | Separate Fold + Stuff summary |
| `meos://finance/accounts` | Masked Fold accounts |
| `meos://health/summary` | Health summary |
| `meos://fitness/progress` | Weight/workout progress |
| `meos://tasks/active` | Today's open tasks |
| `meos://goals` | Life/fitness goals + achievements |
| `meos://events/upcoming` | Next 30 days of projected occurrences |
| `meos://notes/recent` | 20 most recently edited notes |
| `meos://memory/recent` | 20 most relevant memories |
| `meos://devices` | Signed-in devices |
| `meos://capabilities` | Audit inventory |

---

## 8. MCP prompts

- `meos_daily_briefing` — tasks, events, health, diet, money for a date.
- `meos_financial_review` — Fold + Stuff, with explicit no-ledger rules.
- `meos_monthly_review` — goals, tasks, events, training, money, notes, memory.
- `meos_fitness_review` — logged sets and body metrics, calculated targets separated.
- `meos_weekly_planning` — real events + open tasks + goals + program.
- `meos_goal_progress_review` — evidence per goal, never invented percentages.

Every prompt instructs the model to use tools, cite periods, mark calculated values, and avoid exposing
locked/private data.

---

## 9. Client configuration

Use absolute paths; copy `mcp.json.example`.

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "meos": {
      "command": "node",
      "args": [
        "--env-file-if-exists=/absolute/path/to/meOS/mcp/meos/.env",
        "/absolute/path/to/meOS/mcp/meos/src/index.ts"
      ]
    }
  }
}
```

Restart Claude Desktop. Keep the `.env` at mode `600`; do not paste secrets into the JSON.

### Claude Code

```bash
claude mcp add meos --scope user -- \
  node --env-file-if-exists=/absolute/path/to/meOS/mcp/meos/.env \
  /absolute/path/to/meOS/mcp/meos/src/index.ts
```

Or add the `mcpServers` block above to the project's `.mcp.json` (never commit it if it contains secrets).

### Cursor

`.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "meos": {
      "command": "node",
      "args": [
        "--env-file-if-exists=/absolute/path/to/meOS/mcp/meos/.env",
        "/absolute/path/to/meOS/mcp/meos/src/index.ts"
      ]
    }
  }
}
```

### Remote / Streamable HTTP

Start the gateway behind TLS, then point the client at `https://your-host/mcp` with a bearer header.
Claude Code example:

```bash
claude mcp add --transport http meos https://mcp.example.com/mcp \
  --header "Authorization: Bearer $MEOS_MCP_HTTP_TOKEN"
```

Cursor remote server entry:

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

**ChatGPT:** support depends on the connector. Only use a remote MCP connector that can send a custom
`Authorization: Bearer` header. If your plan/connector cannot, put an OAuth-aware proxy in front rather
than weakening this server. Do not expose an unauthenticated endpoint.

---

## 10. Security architecture

- **Authentication.** HTTP requires `Authorization: Bearer`. Tokens are compared as SHA-256 hashes in
  constant time; raw tokens are never retained after startup. Optional `expires_at` enforces expiry.
  stdio relies on the OS process boundary and is launched by the local user.
- **Identity.** The gateway signs in to MeOS with server-side credentials and derives the user from the
  session. No tool has a `user_id`, `account`, or `username` argument. Multiple accounts are isolated by
  separate `AccountServices` (separate cookie, DEK, and state cache).
- **Vault.** The DEK is unwrapped in memory with the existing PBKDF2/AES-GCM implementation. It is never
  logged, returned, or persisted by this process. Without a passphrase the gateway fails closed.
- **Least privilege.** Scope checks happen before handlers and before any record lookup. Destructive
  tools need both the scope and `confirm: true`.
- **Input validation.** Every tool has a Zod input schema, validated again inside the dispatcher. Dates,
  ids, enums, amounts and array sizes are bounded. No arbitrary SQL or table access exists.
- **Rate limiting.** Sliding-window per client (default 120/min), applied once per HTTP request or per
  stdio tool call.
- **Logging.** Structured JSON to stderr. Field names matching token/password/secret/body/content/note/
  transaction/health/args are dropped; only tool name, client id, outcome, duration and key count are
  logged. No payloads.
- **Errors.** Stable codes (`forbidden`, `confirmation_required`, `vault_locked`, `not_found`,
  `invalid_input`, `rate_limited`, `upstream_error`, …) with safe messages. Upstream text is truncated and
  never includes credentials.
- **Transport.** Loopback by default; non-loopback requires explicit opt-in; body size capped; JSON only;
  no GET SSE; no CORS wildcard.
- **Recycle bin.** Deletes capture the whole object (and media keys) in `meos.trash` *before* removing it.
  If the module write fails, the bin entry is rolled back. Nothing is silently destroyed.
- **Media.** Body and event media are vault ciphertext in R2. The gateway returns metadata only and never
  signs or decrypts a URL for an MCP client.

### Changes made to the existing backend

Two small, additive changes were needed for real functionality (no schema migration):

1. `apps/api/src/routes/api/state/[key]/+server.ts` — allowlist `meos.trash` / `myos.trash`. The app
   already pushes `StateKey.trash`; without this, a delete could not be captured and an MCP delete would
   have failed safely.
2. `apps/api/src/lib/server/storage.ts` + `body-photos/+server.ts` — include each object's `bytes` so the
   gateway can report aggregate media usage. The response field is additive; existing clients ignore it.

Existing app functionality, sync, encryption, RLS-era migrations and the diet/stuff MCPs are untouched.

---

## 11. Deployment

### macOS LaunchAgent (stdio is usually unnecessary — the client launches it)

For a persistent HTTP instance, create a LaunchAgent that runs:

```sh
/usr/bin/env node --env-file-if-exists=/path/to/meOS/mcp/meos/.env /path/to/meOS/mcp/meos/src/index.ts
```

with `MEOS_MCP_TRANSPORT=http`. Keep `MEOS_MCP_HTTP_HOST=127.0.0.1` and put Caddy or Cloudflare Tunnel in
front for TLS.

### Linux systemd

```ini
[Unit]
Description=MeOS MCP gateway
After=network-online.target

[Service]
WorkingDirectory=/opt/meOS/mcp/meos
EnvironmentFile=/opt/meOS/mcp/meos/.env
ExecStart=/usr/bin/node --env-file-if-exists=/opt/meOS/mcp/meos/.env src/index.ts
Restart=on-failure
User=meos
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
```

### Caddy

```caddy
mcp.example.com {
  reverse_proxy 127.0.0.1:8788
}
```

Do not expose port 8788 directly. The gateway speaks plain HTTP and expects a trusted TLS terminator.

---

## 12. Testing

```bash
cd mcp/meos
npm test          # 91 tests, node:test
npm run typecheck # tsc --noEmit
```

The suite starts a fake MeOS backend that seals state with the real AES-256-GCM vault implementation, then
drives the tools through the same dispatcher and MCP transport used in production. It covers:

- every tool's schema and registry invariants;
- read, write and destructive permission enforcement;
- missing/invalid/expired bearer tokens;
- two accounts with separate state (user isolation, cross-account `not_found`);
- locked-note and profile redaction;
- pagination and input validation;
- task move/complete/delete/restore;
- recurrence clamping and leap-year occurrences;
- reminder preservation across event updates;
- note rich-attachment preservation;
- diet plan/log semantics and partial food updates;
- recycle-bin capture, restore and media release;
- Streamable HTTP initialize, tools/list, tools/call, resources and prompts;
- HTTP 401/404/405/413 behaviour.

No test needs a real account, network, or secrets.

---

## 13. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `vault_locked` | Set `MEOS_VAULT_PASSPHRASE` (or recovery code). The login password does not unlock the vault. |
| `locked_bad_key` in status | The passphrase is wrong or the meta was rewrapped. Recheck it. No data was changed. |
| `The configured MeOS account could not sign in` | Check `MEOS_USERNAME` / `MEOS_PASSWORD`; the backend never distinguishes wrong user from wrong password. |
| HTTP exits with “refuses to start without credentials” | Set `MEOS_MCP_HTTP_TOKEN` or `MEOS_MCP_CLIENTS_JSON`. |
| HTTP exits with “Refusing to bind” | Keep loopback, or set `MEOS_MCP_ALLOW_REMOTE=true` behind TLS. |
| `forbidden` on health/diet | Grant the `health` scope. Locked notes and body photos also need `secret`. |
| `confirmation_required` | Re-call a destructive tool with `"confirm": true` after user approval. |
| Fold is `linked: false` | Fold is not connected in the app. The gateway refuses to invent balances. |
| `upstream_error` / 503 | The MeOS API is down or the session was revoked; the gateway retries login once. |
| Note edit appears stale in the app | A rich `content` document is authoritative; this gateway rebuilds it from the body while keeping attachments. Reopen the note. |
| Tool call times out | The state document may be large; raise `MEOS_MCP_REQUEST_TIMEOUT_MS` or use paginated tools. |
| Rate limited | Wait for the window or raise `MEOS_MCP_RATE_LIMIT` deliberately. |

---

## 14. Known limitations

- **Last-write-wins sync.** MeOS stores one JSON document per module. The gateway serialises writes inside
  its process and starts each write from a fresh read, but the Mac/iPhone can still write concurrently.
  This is the app's existing sync contract, not something MCP can fix.
- **Seed exercise names are not synced.** Exercise history returns ids; custom exercise names are resolved.
- **No transaction ledger.** Fold exposes balances and category spend only. The Stuff ledger is a purchase
  log with ROI, not a bank feed.
- **No note tags.** The `Note` model has no tag field; do not expect tag filters.
- **No standalone reminders.** A reminder is a lead time on an event. Device notifications belong to the app.
- **Progress photos cannot be restored by MCP.** The files live on the device and in encrypted R2; restore
  is an app action. Metadata is readable with `secret`; bytes never are.
- **ChatGPT connector support varies.** Use a connector that can send a bearer header, or front the
  gateway with an OAuth proxy.
