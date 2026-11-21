# Personal Finance Expansion — Foundation Notes

Status: **shipped (single-document phase)**. No statements have been imported.
No production records were created. The Finance OS UI, ledger engine, demo
data, audit history and tests are implemented. The remaining architecture work
is year-sharding before the first real multi-year import.

> 2026-11-21: the in-progress foundation described below has landed as
> `feat/finance-os`. It keeps the canonical model and storage boundary, adds the
> size guard required before sharding, and does **not** add a server-side
> relational finance table. See `docs/finance-architecture.md`.

## 1. What actually exists today

The brief assumed a full in-app finance module. At the audit base commit
(`4f5de14`) that is **not** what the repository contains. Finance tracking was
deliberately removed in commit `d43476e` ("migrate finance → Fold dashboard"):
the old `FinanceView`, `PortfolioView`, `NetWorthCard`, `TxnReviewSheet` and the
web finance helpers were deleted, and a read-only Fold dashboard replaced them.

| Layer | Present today | Notes |
|---|---|---|
| Swift models | `FoldData`, `FoldSpend` (`Core/LegacyModels.swift`) | Read-only snapshot: net worth, liquid, investments, debt, spends, banks |
| Swift client | `Core/FoldClient.swift`, `Core/FoldSession.swift` | Fold OTP login, encrypted token file, paged transaction fetch used only to build the snapshot |
| Swift UI | `MeMoney` in `MeMoreSub.swift` | Net-worth hero, history sparkline, bank list, top spends, hide toggle |
| Sync | `meos.fold` state key | Snapshot, not a ledger |
| Backend | No finance route, no D1 finance table | `apps/api` stores `meos.fold` as an opaque encrypted document |
| Supabase | `0002_finance.sql` | **Legacy, unused** — accounts/categories/investments/recurring/transactions/savings_goals, RLS, paise integers |
| Tests | None for finance | No finance test target on either platform |

There is also an **in-progress, uncommitted** local-first finance foundation in
the working tree (`apps/apple/MeOS/Core/Finance/`). It is not part of this
cleanup branch and must not be treated as shipped until reviewed and built.

## 2. Capability matrix (at base commit)

| Capability | Existing implementation | Status | Required action |
|---|---|---|---|
| Accounts | Fold bank list only (`FoldData.banks`) | Partial (read-only) | Preserve Fold; build owned accounts |
| Transactions | Fold paged fetch, reduced to top spends; not stored as a ledger | Partial (read-only) | Build |
| Categories | Fold category strings on spends; no taxonomy | Missing | Build |
| Transfers | None | Missing | Build |
| Budgets | Legacy Supabase `categories.monthly_budget_paise` only | Missing at runtime | Build |
| Investments | Fold aggregate stocks + MF values; no holdings/units | Partial (read-only) | Improve / build holdings |
| Liabilities | Fold `debt` total; no loan/card accounts | Partial (read-only) | Build |
| Net worth | Fold snapshot `netWorth` | Working (read-only) | Preserve; also derive from ledger |
| Statement imports | None | Missing | Build (next phase) |
| Reconciliation | None | Missing | Build |
| Financial reports | Fold dashboard tiles + sparkline | Partial | Improve |
| Audit history | App recycle bin covers deleted objects, not finance edits | Missing | Build append-only audit |
| Recurring | Legacy Supabase table only | Missing at runtime | Build |
| Finance goals | Legacy `savings_goals` only | Missing at runtime | Build |

## 3. Recommended architecture

### 3.1 Local-first, sharded encrypted documents

MeOS is zero-knowledge: the server stores ciphertext per module and cannot read
it. Adding a server-side relational finance schema would either expose amounts
(against the product's privacy model) or produce unqueryable encrypted columns.
Keep finance on-device and synced like every other module.

A single `meos.finance` document will not fit a lifetime of history: D1's value
limit is 2 MB and the API caps writes at 1.9 MB. Shard it:

```
meos.finance                 settings, categories, accounts, budgets,
                             goals, recurring rules, import metadata index
meos.finance.tx.<yyyy>       transactions for one calendar year
meos.finance.tx.<yyyy>.<n>   overflow page if a year exceeds the cap
meos.finance.audit.<yyyy>    append-only audit entries for one year
meos.finance.import.<id>     one staged statement-import batch
```

Rules:

- Each document is independently encrypted and independently pushed. A year page
  is only rewritten when that year changes.
- The client aggregates months/years for reports; cache derived totals in
  memory (and optionally a small `meos.finance.reports` document).
- The server allowlist must support a **prefix**, not exact keys:
  `^meos\.finance(\.[a-z0-9._-]{1,60})?$`, still bounded by length and the byte
  cap. Add a test with every generated shape.
- Never put plaintext amounts, payees or account numbers in a key name.

If the in-progress single-document implementation ships first, keep its model
and storage boundary, add a size guard, and migrate to shards before the first
multi-year import. Do not rewrite identifiers during that split.

### 3.2 Canonical model

All money is integer **minor units** (paise) and each amount carries a currency;
INR is the base. Dates are `yyyy-MM-dd`; instants are ISO-8601 UTC.

- **Account**: id, name, kind (`bank|cash|credit_card|upi|wallet|deposit|loan|
  investment`), institution, currency, `opening_on`, `opening_balance_minor`,
  archived, ownership (`self|joint|other`), last4 (optional, never full number).
- **Posting/Transaction**: id, accountId, date, signed `amount_minor`, currency,
  kind (`expense|income|transfer|refund|fee|interest|adjustment`), categoryId,
  payee, note, `transfer_id`, `source` (`manual|import|csv|fold|recurring`),
  `external_id`, `import_batch_id`, `status` (`pending|cleared|reconciled`),
  `created_at`, `updated_at`.
- **Transfer**: one logical transfer with exactly two postings (from/to), same
  `transfer_id`. Reports must count it once; balances see both sides.
- **Refund**: an income posting linked to the original expense (optional
  `refund_of`), not a negative expense, so category reports stay honest.
- **Category**: id, name, parentId (one level), kind, icon/colour, archived.
  Budgets reference category ids, never names.
- **Budget**: period (`month|year|custom`), categoryId or total, amount, rollover.
- **Investment**: instrument, kind, currency, units, cost basis, current value;
  **Valuation** records value on a date so history is not overwritten.
- **Liability**: principal, rate, EMI, tenure, due day, linked account; payments
  are transfers/postings, not mutations of the principal.
- **Goal**: target, target date, linked account(s), contributions.
- **Recurring rule**: cadence, next run, account, category, amount, active.
- **ImportBatch + ImportRow**: file hash, account, period, raw row, parsed row,
  status, error, duplicate candidate. Staged rows never post automatically.
- **AuditEntry**: append-only `{id, at, actor, action, entity, entityId,
  beforeHash, afterHash, reason}`. Corrections add entries; they never erase the
  prior value. Keep the recycled object for 30 days as today.

### 3.3 Historical reconstruction

- Every account gets an explicit opening balance and opening date. The ledger is
  the sum of postings after that date; never carry a mutable "current balance"
  as the source of truth.
- A statement import establishes a period, not a new opening balance. The
  opening balance for the next period is the previous closing balance.
- Support pre-ledger "balance-only" anchors (a date + balance with no rows) for
  years where statements are missing, so net-worth history is still honest.
- Net worth as of date = assets − liabilities, using valuations as of that date.
- Multi-year reports read the year shards and aggregate; no destructive rollups.
- Keep original currency and FX rate used at posting time if multi-currency is
  ever needed.

### 3.4 Import pipeline (next phase, not this task)

1. Upload/select a statement; hash the file; detect duplicates.
2. Parse into **staged rows**; never write the ledger directly.
3. Normalise date, amount sign, payee, and account; classify candidates.
4. Detect exact duplicates (`account + external_id`) and fuzzy duplicates
   (same amount, date ±3 days, normalised payee).
5. Human review screen: accept / skip / merge / split transfer.
6. Post accepted rows with `source` + `import_batch_id` + `external_id`.
7. Reconcile: compare computed balance to statement closing; record an audited
   adjustment if they differ, never silently edit rows.
8. Keep the batch and raw rows for audit and re-import safety.

No importer, sample statement, or fabricated record is added in this task.

## 4. Deliberate non-goals for the cleanup phase

- No production database migration. The legacy Supabase finance tables stay as
  a reference; the live D1 schema is untouched by finance work.
- No replacement of Fold. Fold remains the read-only live banking dashboard;
  the new ledger is for ownership, history and reporting.
- No UI redesign and no request for statements.
- No plaintext finance data on the server or in logs.

## 5. Files the next phase should touch

Apple:

- `apps/apple/MeOS/Core/Finance/FinanceModels.swift` — canonical model and
  coding keys; keep IDs stable.
- `apps/apple/MeOS/Core/Finance/FinanceEngine.swift` — pure derivations
  (balances, net worth, reports, duplicate detection, integrity checks).
- `apps/apple/MeOS/Core/Finance/FinanceStore.swift` — shard load/save, import
  staging, audit append; the only writer.
- `apps/apple/MeOS/MeFinance.swift` + `MeFinanceKit.swift` — screens.
- `apps/apple/MeOS/Core/Models.swift` — `StateKey.finance` and payload fields.
- `apps/apple/MeOS/Core/AppState.swift` — hydrate/apply/push/export/logout and
  key migration. Do **not** purge `meos.finance`; the one-shot purge is only for
  the removed `myos.finance`/`myos.portfolio`/`myos.networth`.
- `apps/apple/MeOS/MeShell.swift`, `MeMacShell.swift`, `MeMore.swift` — tab and
  sidebar placement.
- `apps/apple/project.yml` — no change needed if the Finance folder stays under
  the `MeOS` source path; re-run xcodegen.

Backend:

- `apps/api/src/lib/server/stateKeys.ts` — finance prefix allowlist + test.
- `apps/api/src/routes/api/state/[key]/+server.ts` — no shape change; it already
  enforces auth, the allowlist and the 1.9 MB cap.
- `apps/api/src/lib/server/stateKeys.test.ts` — one fixture per shard shape.
- No new API route is required for a local-first ledger. Add one only if a
  server-side report/export is chosen later.

Docs and tests:

- `docs/finance-foundation.md` (this file) — keep the model and limits current.
- Add a finance test target or pure Swift tests for `FinanceEngine` before UI:
  balances, transfer double-count, refunds, opening balances, duplicate
  detection, leap-day/period boundaries, audit append.
