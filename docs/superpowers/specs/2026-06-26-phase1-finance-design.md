# MyOS — Phase 1 Finance — Design Spec

**Date:** 2026-06-26
**Status:** Approved for build
**Owner:** Berjil
**Parent spec:** `2026-06-26-myos-design.md` (§5 data model, §8 finance UX)

---

## 1. Purpose

Build the Finance module so every rupee of income/expense is tracked from day 1, with exact integer-paise money math ("not 1 rupee missed"). Ships as a single Phase 1 plan, internally staged.

## 2. Scope

All 9 Phase 1 deliverables in one plan: accounts, transactions, 3-second quick-add, categories + budgets, recurring + salary, subscriptions, savings goals, investments/SIPs, finance dashboard.

Built on existing Phase 0 foundation: `money.ts`, `data/repository.ts` (`SupabaseRepository<T>`), `data/sync-queue.ts`, `data/db.ts` (Dexie), Supabase auth + RLS, app shell, 3 themes.

## 3. Locked decisions (this phase)

| Decision | Choice | Reason |
|---|---|---|
| Slicing | All 9 deliverables, one plan, 7 internal stages | Owner wants complete module; stages keep it buildable |
| Account balance | Stored cache + recompute/reconcile | Fast reads; drift detected + repaired → correctness guaranteed |
| Recurring due | Catch-up on app open (idempotent) | No backend cron; offline-friendly PWA; nothing missed |
| Offline | Write offline (existing queue) + read from Query cache | Smallest correct increment; full Dexie read-mirror deferred |
| Transfers | Single row, `account_id` (from) + `transfer_account_id` (to) | Simple; always nets to zero across accounts |
| Investments value | Manual `current_value_paise` entry | No market API (matches parent non-goals) |
| SIP | Recurring contribution via catch-up + bump `invested_paise` | Reuses recurring engine |
| Savings goal contribution | A transaction that bumps `saved_paise` | One money path, no special-case ledger |

## 4. Architecture

### 4.1 Data-access layer — `src/lib/finance/`
- Typed repos per table, thin wrappers over the generic `SupabaseRepository<T>`.
- Focused service modules holding money logic: `accounts.ts`, `transactions.ts`, `recurring.ts`, `budgets.ts`, `goals.ts`, `investments.ts`.
- Money helpers extend `src/lib/money.ts`: `sumPaise`, `budgetRollup`, balance recompute. All arithmetic in integer paise; INR formatting only at display via `formatINR` (`Intl.NumberFormat('en-IN')`).

### 4.2 Schema — migration `supabase/migrations/0002_finance.sql`
Tables per parent spec §5: `accounts`, `categories`, `transactions`, `recurring`, `savings_goals`, `investments`. Subscriptions modeled as `recurring.kind='subscription'` with optional `vendor`, `plan`, `renews_on`.

Every table:
- `user_id` (default `auth.uid()`).
- **RLS enabled**, policy `user_id = auth.uid()` for select/insert/update/delete.
- `created_at`, `updated_at` (+ trigger), indexes on FKs and `occurred_on`.

Seed a set of default expense/income categories on first run.

### 4.3 Money correctness (the "not 1 rupee" core)
- `accounts.balance_paise` = opening balance; live balance maintained on every write (insert/edit/delete/transfer).
- `reconcileAccount()` recomputes balance from all transactions, detects drift, repairs it. Runs on app open + manual "reconcile" action.
- Transfer recompute subtracts from source account, adds to destination → nets to zero.
- Budget rollup = sum of month's expense transactions per category vs `monthly_budget_paise`.

### 4.4 Recurring catch-up (on app open)
Query `recurring` where `active AND next_run_on <= today`. For each: create transaction(s) up to today, advance `next_run_on` by cadence, loop. Idempotent — guarded by `(recurring_id, occurred_on)` so re-opening never double-posts. Auto-created transactions are editable/deletable. SIPs post a contribution and bump `investments.invested_paise`.

## 5. UI / routes — `src/routes/(app)/finance/`

- **`/finance`** — dashboard: month nav (prev/next), net worth, this-month income/expense, budget rings, spend-by-category donut, account balances, upcoming recurring + subscriptions, SIP/investment summary.
- **`/finance/transactions`** — list + filter (account / category / month) + search.
- **`/finance/accounts`**, **`/finance/budgets`**, **`/finance/goals`**, **`/finance/investments`** — module views.
- **Quick-add** — global FAB → sheet: amount pad → category chip → account → save; date defaults today. 3-second logging.

### 5.1 Charts — port, don't import
`MiniRingChart` / `DonutChart` live in the read-only monorepo and cannot be imported. Port them into `src/lib/components/charts/` as Svelte 5 components. Reuse existing shadcn-svelte primitives and `kn-` entrance animations.

### 5.2 Offline write path
Quick-add + edits go through `sync-queue.ts` → optimistic TanStack Query update → sync on reconnect. Reads from Query cache. Full Dexie read-mirror deferred to a later hardening pass.

## 6. Testing

- **Vitest:** balance recompute, transfer nets-zero, budget rollup, recurring catch-up idempotency, reconcile drift-repair. Money math tested hard.
- **RLS test** per new table — owner-only isolation proven, not assumed.
- **Playwright:** quick-add flow; offline-then-sync.

## 7. Build stages (one plan, sequential)

1. Migration `0002` + RLS + policy tests + seed categories.
2. Finance domain layer + money helpers + unit tests.
3. Accounts + Transactions + quick-add.
4. Categories + Budgets + dashboard (charts ported).
5. Recurring + subscriptions + catch-up.
6. Savings goals + Investments/SIP.
7. Offline write wired + Playwright e2e.

## 8. Non-goals (this phase)

- No full Dexie offline read-mirror (deferred hardening pass).
- No bank/UPI auto-sync, no market price API.
- No backend cron (catch-up is client-side on app open).
- No multi-user.
