# Personal Finance — audit record and current state

Status: **shipped (single-document phase)**. No real statements have been
imported. Current implementation details live in
[`finance-architecture.md`](finance-architecture.md); this file records the
audit that started the work and the remaining storage step.

## 1. What the audit found (historical)

At audit base commit `4f5de14`, the full in-app finance module did **not**
exist. Finance tracking had been deliberately removed in `d43476e` ("migrate
finance → Fold dashboard"): `FinanceView`, `PortfolioView`, `NetWorthCard`,
`TxnReviewSheet` and the web finance helpers were deleted, and a read-only Fold
dashboard replaced them.

| Layer at base | State |
|---|---|
| Swift models | `FoldData`, `FoldSpend` — read-only Fold snapshot |
| Swift UI | `MeMoney` — net worth, history, banks, top spends |
| Sync | `meos.fold` only |
| Backend | No finance route or D1 table |
| Supabase | `0002_finance.sql` — legacy reference, never runtime |
| Tests | None for finance |

### Capability matrix at base

| Capability | Then | Now |
|---|---|---|
| Accounts | Fold bank list only | **Built** — owned accounts |
| Transactions | Fold top spends only | **Built** — auditable ledger |
| Categories | Fold strings only | **Built** — stable taxonomy |
| Transfers | Missing | **Built** — paired postings |
| Budgets | Legacy Supabase only | **Built** |
| Investments | Fold totals only | **Built** — holdings + valuations |
| Liabilities | Fold debt total only | **Built** — loans/cards/EMI |
| Net worth | Fold snapshot | **Built** — dated history + certainty |
| Statement imports | Missing | **Partial** — workspace ready; parser is next |
| Reconciliation | Missing | **Built** — statement anchors |
| Financial reports | Fold tiles | **Built** — reports/tax/timeline |
| Audit history | Missing | **Built** — append-only entries |
| Recurring / goals | Legacy Supabase only | **Built** |

## 2. What shipped

- Native SwiftUI Finance module for Mac and iPhone
  (`apps/apple/MeOS/MeFinance*.swift`).
- Encrypted `meos.finance` document with stable IDs and audit entries
  (`Core/Finance/FinanceModels.swift`).
- Pure calculation engine (`FinanceEngine.swift`) and its 29 domain tests in
  `apps/apple/Tests/FinanceCoreTests`.
- Explicit, fictional demo dataset (`FinanceDemo.swift`), badged and removable.
- Finance tools in the central MCP gateway (`mcp/meos`), including the encrypted
  ledger, with `read`/`write` scopes.
- Fold remains a separate, read-only banking snapshot. It is never mixed into
  the ledger.

## 3. Remaining work before real history

`meos.finance` is one document today, with a **1.3 MB plaintext guard** and a
1.9 MB API/D1 ceiling. The demo document already measures ~1.1 MB, so real
multi-year history must be sharded before the first import:

```
meos.finance                 settings, accounts, categories, budgets, goals,
                             recurring rules, import metadata
meos.finance.tx.<yyyy>       one year of transactions
meos.finance.tx.<yyyy>.<n>   overflow page
meos.finance.audit.<yyyy>    append-only audit entries
meos.finance.import.<id>     one staged import batch
```

The server prefix is already allowlisted and tested. The model and IDs do not
change; only the storage boundary moves. Statement parsing, duplicate detection,
reconciliation review and multi-year reporting are the next phase.

## 4. Deliberate non-goals

- No server-side relational finance tables and no plaintext amounts on the
  server.
- No legacy Supabase migration.
- No automatic import; statements are staged and reviewed.
- No invented transactions or balances.
