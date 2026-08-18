# MyOS Phase 1 — Finance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Finance module — accounts, transactions, 3-second quick-add, categories + budgets, recurring/salary/subscriptions, savings goals, investments/SIPs, and a finance dashboard — with exact integer-paise money math so no rupee is ever lost.

**Architecture:** A pure money/calc layer (no I/O, exhaustively unit-tested) sits under a thin domain layer (`src/lib/finance/*`) built on the existing `SupabaseRepository<T>`. Postgres holds 6 finance tables, each RLS-guarded to the owner. Account balances are a stored cache repaired by a pure reconcile function. Recurring items post on app-open via an idempotent catch-up. UI lives under `src/routes/(app)/finance/*` with quick-add and ported SVG ring/donut charts; writes flow through the existing offline mutation queue.

**Tech Stack:** SvelteKit 2, Svelte 5 (runes), TypeScript (strict), Bun, Tailwind v4, shadcn-svelte ("luma"), Bits UI, TanStack Svelte Query, Supabase (Postgres + Auth), Dexie, Vitest, Playwright.

## Global Constraints

- **Package manager / runtime:** Bun. Dev server port **5177**.
- **Language:** TypeScript strict mode. `bun run check` must report **0 errors** before any commit.
- **Money:** integer **paise** (BIGINT in DB, `number` in TS) everywhere. Never store or compute money as float. Convert with `toPaise`/`fromPaise`, display with `formatINR` — all from `src/lib/money.ts`.
- **Privacy:** single owner. Every new table: RLS enabled, policy `user_id = auth.uid()` for all of select/insert/update/delete, `grant ... to authenticated` (never `anon`). Add an RLS isolation test for every new table.
- **Data access:** go through `src/lib/finance/*` services (which wrap `SupabaseRepository<T>` from `src/lib/data/repository.ts`). Offline writes go through `enqueue()` in `src/lib/data/sync-queue.ts`.
- **Component import convention:** `import * as Card from '$lib/components/ui/card'` then `<Card.Root>`. Class merge via `cn()` from `$lib/utils`.
- **TanStack Query is the Svelte-5 runes adapter (v6).** `createQuery(() => ({...}))` / `createMutation(() => ({...}))` return reactive RESULT OBJECTS — access them directly: `accounts.data`, `save.isPending`, `save.mutate()`. **Do NOT use the `$store` prefix** (`$accounts.data` is wrong and fails type-check). The options argument must be a function returning the options object. (The component snippets below were drafted with the older `$`-store style — drop the `$` on query/mutation results when implementing; `$state`/`$derived`/`$props`/`$effect` are runes and stay.)
- **Animations:** wrap list/section roots in `kn-stagger`; cards use existing entrance classes.
- **Charts:** port as self-contained SVG Svelte components into `src/lib/components/charts/`. Do NOT import from the monorepo (read-only reference).
- **Test commands:** `bun run test -- --run` (unit), `bun run check` (types), `bunx playwright test` (e2e). RLS test needs the local stack and `SUPABASE_ANON_KEY` (see CLAUDE.md).
- **Commits:** one per task minimum, conventional-commit messages. Author is the repo default (`berjilberjil <berjiljacob@gmail.com>`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## File Structure

```
supabase/migrations/
  0002_finance.sql                    # 6 tables + RLS + grants + seed categories + indexes

src/lib/
  money.ts                            # MODIFY: add sumPaise()
  finance/
    types.ts                          # Account, Category, Transaction, Recurring, SavingsGoal, Investment + enums
    dates.ts                          # pure date helpers: todayIso, monthKey, monthRange, advanceDate
    calc.ts                           # PURE money math: balanceDelta, balanceFromTransactions, budgetRollup, catchUpOccurrences
    accounts.ts                       # accountsRepo, netWorth, reconcileAccount, reconcileAll
    transactions.ts                   # txnRepo, createTransaction, updateTransaction, deleteTransaction, listByMonth
    categories.ts                     # categoriesRepo, seedDefaultCategories
    budgets.ts                        # monthBudgetLines
    recurring.ts                      # recurringRepo, runCatchUp, dueSoon
    goals.ts                          # goalsRepo, contributeToGoal
    investments.ts                    # investmentsRepo, setCurrentValue

src/lib/components/
  charts/
    MiniRingChart.svelte              # SVG progress ring (budget rings)
    DonutChart.svelte                 # SVG donut (spend-by-category)
  finance/
    QuickAdd.svelte                   # global FAB → dialog: amount pad → category → account → save
    TransactionRow.svelte            # one transaction line (shared by list + dashboard)
    MonthNav.svelte                   # prev/next month header (shared)

src/routes/(app)/finance/
  +layout.svelte                      # finance sub-nav (pill tabs) + runs catch-up + reconcile on mount
  +page.svelte                        # dashboard
  transactions/+page.svelte           # list + filters + search
  accounts/+page.svelte               # accounts CRUD
  budgets/+page.svelte                # categories + budgets CRUD + rings
  goals/+page.svelte                  # savings goals + contribute
  investments/+page.svelte            # investments + SIP

tests/unit/
  finance-dates.test.ts
  finance-calc.test.ts
  finance-accounts.test.ts            # reconcile (mocked repo)
  finance-recurring.test.ts           # catch-up idempotency (mocked repo)
  finance-rls.test.ts                 # owner isolation for finance tables
tests/e2e/
  finance-quickadd.spec.ts            # quick-add flow + offline-then-sync
```

**Stages (each ends shippable):** 1 Schema → 2 Pure calc + dates → 3 Domain services → 4 Accounts + Transactions + Quick-add → 5 Categories + Budgets + Dashboard → 6 Recurring + Subscriptions → 7 Goals + Investments + offline e2e.

---

## Stage 1 — Schema

### Task 1: Finance migration (6 tables + RLS + seed)

**Files:**
- Create: `supabase/migrations/0002_finance.sql`
- Test: `tests/unit/finance-rls.test.ts`

**Interfaces:**
- Produces (DB tables consumed by every later task): `accounts(id, name, type, opening_balance_paise, balance_paise, currency, archived)`, `categories(id, name, kind, icon, color, monthly_budget_paise)`, `transactions(id, account_id, category_id, type, amount_paise, transfer_account_id, note, occurred_on, recurring_id)`, `recurring(id, kind, name, amount_paise, account_id, category_id, cadence, interval_days, next_run_on, active, vendor, plan, renews_on, investment_id)`, `savings_goals(id, name, target_paise, saved_paise, deadline, account_id)`, `investments(id, name, type, invested_paise, current_value_paise, sip_amount_paise, sip_day)`. All include `user_id`, `created_at`, `updated_at`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0002_finance.sql`:

```sql
-- Finance schema. Money is integer paise (bigint). Owner-only via RLS.

create table accounts (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	type text not null check (type in ('bank','cash','upi','credit_card','wallet')),
	opening_balance_paise bigint not null default 0,
	balance_paise bigint not null default 0,
	currency text not null default 'INR',
	archived boolean not null default false,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index accounts_user_idx on accounts (user_id, archived);

create table categories (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	kind text not null check (kind in ('expense','income')),
	icon text,
	color text,
	monthly_budget_paise bigint not null default 0,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index categories_user_idx on categories (user_id, kind);

create table investments (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	type text not null check (type in ('sip','mutual_fund','stock','other')),
	invested_paise bigint not null default 0,
	current_value_paise bigint not null default 0,
	sip_amount_paise bigint,
	sip_day int check (sip_day between 1 and 28),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index investments_user_idx on investments (user_id);

create table recurring (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	kind text not null check (kind in ('income','expense','subscription')),
	name text not null,
	amount_paise bigint not null,
	account_id uuid not null references accounts(id) on delete cascade,
	category_id uuid references categories(id) on delete set null,
	cadence text not null check (cadence in ('monthly','weekly','custom')),
	interval_days int,
	next_run_on date not null,
	active boolean not null default true,
	vendor text,
	plan text,
	renews_on date,
	investment_id uuid references investments(id) on delete set null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index recurring_due_idx on recurring (user_id, active, next_run_on);

create table transactions (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	account_id uuid not null references accounts(id) on delete cascade,
	category_id uuid references categories(id) on delete set null,
	type text not null check (type in ('income','expense','transfer')),
	amount_paise bigint not null check (amount_paise >= 0),
	transfer_account_id uuid references accounts(id) on delete cascade,
	note text,
	occurred_on date not null,
	recurring_id uuid references recurring(id) on delete set null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	check (type <> 'transfer' or transfer_account_id is not null)
);
create index transactions_month_idx on transactions (user_id, occurred_on);
create index transactions_account_idx on transactions (user_id, account_id);
-- Idempotency guard for recurring catch-up: at most one txn per recurring item per day.
create unique index transactions_recurring_uq on transactions (recurring_id, occurred_on)
	where recurring_id is not null;

create table savings_goals (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	target_paise bigint not null,
	saved_paise bigint not null default 0,
	deadline date,
	account_id uuid references accounts(id) on delete set null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index savings_goals_user_idx on savings_goals (user_id);

-- updated_at trigger
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end; $$ language plpgsql;

create trigger accounts_set_updated before update on accounts for each row execute function set_updated_at();
create trigger categories_set_updated before update on categories for each row execute function set_updated_at();
create trigger investments_set_updated before update on investments for each row execute function set_updated_at();
create trigger recurring_set_updated before update on recurring for each row execute function set_updated_at();
create trigger transactions_set_updated before update on transactions for each row execute function set_updated_at();
create trigger savings_goals_set_updated before update on savings_goals for each row execute function set_updated_at();

-- RLS: owner-only on every finance table.
alter table accounts enable row level security;
alter table categories enable row level security;
alter table investments enable row level security;
alter table recurring enable row level security;
alter table transactions enable row level security;
alter table savings_goals enable row level security;

create policy "own accounts" on accounts for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own categories" on categories for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own investments" on investments for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own recurring" on recurring for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own transactions" on transactions for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own savings_goals" on savings_goals for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on table
	accounts, categories, investments, recurring, transactions, savings_goals to authenticated;
```

- [ ] **Step 2: Apply migration to local stack**

Run: `bunx supabase start && bunx supabase migration up`
Expected: migration `0002_finance` applies with no error; `bunx supabase db reset` also succeeds.

- [ ] **Step 3: Write the RLS isolation test**

Create `tests/unit/finance-rls.test.ts` (mirrors `tests/unit/rls.test.ts`). Public signup is disabled (`config.toml` `enable_signup = false`), so users are created via the admin API (service_role), not `signUp`:

```ts
import { describe, it, expect } from 'vitest';
import { createClient } from '@supabase/supabase-js';

const URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const ANON = process.env.SUPABASE_ANON_KEY ?? '';
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

async function userClient(email: string) {
	const admin = createClient(URL, SERVICE, { auth: { autoRefreshToken: false, persistSession: false } });
	await admin.auth.admin.createUser({ email, password: 'Passw0rd!test', email_confirm: true });
	const c = createClient(URL, ANON);
	await c.auth.signInWithPassword({ email, password: 'Passw0rd!test' });
	return c;
}

describe.skipIf(!ANON || !SERVICE)('finance RLS isolation', () => {
	it('a user cannot read another user accounts', async () => {
		const stamp = `${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
		const a = await userClient(`fa_${stamp}@t.test`);
		const { error: insErr } = await a.from('accounts').insert({ name: 'HDFC', type: 'bank' });
		expect(insErr).toBeNull();

		const b = await userClient(`fb_${stamp}@t.test`);
		const { data } = await b.from('accounts').select('*');
		expect(data).toEqual([]);
	});
});
```

- [ ] **Step 4: Run the RLS test against the local stack**

Run:
```bash
export SUPABASE_ANON_KEY="$(bunx supabase status -o env | grep '^ANON_KEY=' | cut -d'"' -f2)"
export SUPABASE_SERVICE_ROLE_KEY="$(bunx supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d'"' -f2)"
bun run test -- --run tests/unit/finance-rls.test.ts
```
Expected: PASS (B sees none of A's rows).

- [ ] **Step 5: Regenerate DB types**

Run: `bunx supabase gen types typescript --local > src/lib/supabase/types.ts`
Then `bun run check`. Expected: 0 errors; `types.ts` now contains the 6 finance tables.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/0002_finance.sql tests/unit/finance-rls.test.ts src/lib/supabase/types.ts
git commit -m "feat(finance): schema + RLS for accounts, categories, transactions, recurring, goals, investments"
```

---

## Stage 2 — Pure calc + dates (the correctness core)

### Task 2: Finance types

**Files:**
- Create: `src/lib/finance/types.ts`

**Interfaces:**
- Produces: all domain types + enum unions used by every later task. Exact names below.

- [ ] **Step 1: Write the types** (no test — pure type declarations, validated by `bun run check` in later tasks)

Create `src/lib/finance/types.ts`:

```ts
export type AccountType = 'bank' | 'cash' | 'upi' | 'credit_card' | 'wallet';
export type CategoryKind = 'expense' | 'income';
export type TxnType = 'income' | 'expense' | 'transfer';
export type RecurringKind = 'income' | 'expense' | 'subscription';
export type Cadence = 'monthly' | 'weekly' | 'custom';
export type InvestmentType = 'sip' | 'mutual_fund' | 'stock' | 'other';

export interface Account {
	id: string;
	user_id: string;
	name: string;
	type: AccountType;
	opening_balance_paise: number;
	balance_paise: number;
	currency: string;
	archived: boolean;
	created_at: string;
	updated_at: string;
}

export interface Category {
	id: string;
	user_id: string;
	name: string;
	kind: CategoryKind;
	icon: string | null;
	color: string | null;
	monthly_budget_paise: number;
	created_at: string;
	updated_at: string;
}

export interface Transaction {
	id: string;
	user_id: string;
	account_id: string;
	category_id: string | null;
	type: TxnType;
	amount_paise: number;
	transfer_account_id: string | null;
	note: string | null;
	occurred_on: string; // 'YYYY-MM-DD'
	recurring_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface Recurring {
	id: string;
	user_id: string;
	kind: RecurringKind;
	name: string;
	amount_paise: number;
	account_id: string;
	category_id: string | null;
	cadence: Cadence;
	interval_days: number | null;
	next_run_on: string; // 'YYYY-MM-DD'
	active: boolean;
	vendor: string | null;
	plan: string | null;
	renews_on: string | null;
	investment_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface SavingsGoal {
	id: string;
	user_id: string;
	name: string;
	target_paise: number;
	saved_paise: number;
	deadline: string | null;
	account_id: string | null;
	created_at: string;
	updated_at: string;
}

export interface Investment {
	id: string;
	user_id: string;
	name: string;
	type: InvestmentType;
	invested_paise: number;
	current_value_paise: number;
	sip_amount_paise: number | null;
	sip_day: number | null;
	created_at: string;
	updated_at: string;
}
```

- [ ] **Step 2: Verify it type-checks**

Run: `bun run check`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add src/lib/finance/types.ts
git commit -m "feat(finance): domain types"
```

### Task 3: sumPaise helper

**Files:**
- Modify: `src/lib/money.ts`
- Test: `tests/unit/money.test.ts`

**Interfaces:**
- Produces: `sumPaise(values: number[]): number`

- [ ] **Step 1: Add the failing test** — append inside `describe('money', ...)` in `tests/unit/money.test.ts`:

```ts
	it('sums paise with no float drift', () => {
		expect(sumPaise([1999, 1, 4000000])).toBe(4002000);
		expect(sumPaise([])).toBe(0);
	});
```

Also extend the import line: `import { toPaise, fromPaise, formatINR, sumPaise } from '$lib/money';`

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/money.test.ts`
Expected: FAIL — `sumPaise is not a function`.

- [ ] **Step 3: Implement** — append to `src/lib/money.ts`:

```ts
export function sumPaise(values: number[]): number {
	return values.reduce((total, v) => total + v, 0);
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/money.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/money.ts tests/unit/money.test.ts
git commit -m "feat(money): sumPaise"
```

### Task 4: Date helpers

**Files:**
- Create: `src/lib/finance/dates.ts`
- Test: `tests/unit/finance-dates.test.ts`

**Interfaces:**
- Produces: `todayIso(): string`, `monthKey(iso: string): string`, `monthRange(year: number, month1: number): { start: string; end: string }` (month1 is 1–12), `advanceDate(iso: string, cadence: Cadence, intervalDays: number | null): string`. All dates are `'YYYY-MM-DD'` strings, computed in UTC to avoid timezone drift.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/finance-dates.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { monthKey, monthRange, advanceDate } from '$lib/finance/dates';

describe('finance dates', () => {
	it('monthKey extracts YYYY-MM', () => {
		expect(monthKey('2026-06-26')).toBe('2026-06');
	});
	it('monthRange returns first and last day', () => {
		expect(monthRange(2026, 2)).toEqual({ start: '2026-02-01', end: '2026-02-28' });
		expect(monthRange(2024, 2)).toEqual({ start: '2024-02-01', end: '2024-02-29' });
		expect(monthRange(2026, 6)).toEqual({ start: '2026-06-01', end: '2026-06-30' });
	});
	it('advanceDate monthly adds one month', () => {
		expect(advanceDate('2026-01-31', 'monthly', null)).toBe('2026-02-28');
		expect(advanceDate('2026-06-15', 'monthly', null)).toBe('2026-07-15');
	});
	it('advanceDate weekly adds 7 days', () => {
		expect(advanceDate('2026-06-26', 'weekly', null)).toBe('2026-07-03');
	});
	it('advanceDate custom adds intervalDays', () => {
		expect(advanceDate('2026-06-26', 'custom', 10)).toBe('2026-07-06');
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-dates.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `src/lib/finance/dates.ts`:

```ts
import type { Cadence } from './types';

function pad(n: number): string {
	return n < 10 ? `0${n}` : `${n}`;
}
function fmt(d: Date): string {
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}
function parse(iso: string): Date {
	const [y, m, day] = iso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, day));
}

export function todayIso(): string {
	return fmt(new Date());
}

export function monthKey(iso: string): string {
	return iso.slice(0, 7);
}

export function monthRange(year: number, month1: number): { start: string; end: string } {
	const start = new Date(Date.UTC(year, month1 - 1, 1));
	const end = new Date(Date.UTC(year, month1, 0)); // day 0 of next month = last day of this one
	return { start: fmt(start), end: fmt(end) };
}

export function advanceDate(iso: string, cadence: Cadence, intervalDays: number | null): string {
	const d = parse(iso);
	if (cadence === 'weekly') {
		d.setUTCDate(d.getUTCDate() + 7);
		return fmt(d);
	}
	if (cadence === 'custom') {
		d.setUTCDate(d.getUTCDate() + (intervalDays ?? 0));
		return fmt(d);
	}
	// monthly: clamp to the last valid day of the target month (e.g. Jan 31 -> Feb 28)
	const day = d.getUTCDate();
	const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1));
	const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
	target.setUTCDate(Math.min(day, lastDay));
	return fmt(target);
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-dates.test.ts`
Expected: PASS (all 5).

- [ ] **Step 5: Commit**

```bash
git add src/lib/finance/dates.ts tests/unit/finance-dates.test.ts
git commit -m "feat(finance): pure date helpers"
```

### Task 5: Pure money calc — balances, budgets, catch-up

**Files:**
- Create: `src/lib/finance/calc.ts`
- Test: `tests/unit/finance-calc.test.ts`

**Interfaces:**
- Produces:
  - `balanceDelta(t: Transaction, accountId: string): number`
  - `balanceFromTransactions(openingPaise: number, txns: Transaction[], accountId: string): number`
  - `budgetRollup(categories: Category[], monthTxns: Transaction[]): BudgetLine[]` where `BudgetLine = { category_id: string; name: string; spent_paise: number; budget_paise: number }`
  - `catchUpOccurrences(nextRunOn: string, cadence: Cadence, intervalDays: number | null, todayIso: string): { dates: string[]; nextRunOn: string }`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/finance-calc.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { balanceDelta, balanceFromTransactions, budgetRollup, catchUpOccurrences } from '$lib/finance/calc';
import type { Transaction, Category } from '$lib/finance/types';

function txn(p: Partial<Transaction>): Transaction {
	return {
		id: 't', user_id: 'u', account_id: 'A', category_id: null, type: 'expense',
		amount_paise: 0, transfer_account_id: null, note: null, occurred_on: '2026-06-01',
		recurring_id: null, created_at: '', updated_at: '', ...p
	};
}

describe('balanceDelta', () => {
	it('income adds, expense subtracts for the owning account', () => {
		expect(balanceDelta(txn({ type: 'income', amount_paise: 5000, account_id: 'A' }), 'A')).toBe(5000);
		expect(balanceDelta(txn({ type: 'expense', amount_paise: 5000, account_id: 'A' }), 'A')).toBe(-5000);
	});
	it('transfer leaves source and enters destination, netting to zero', () => {
		const t = txn({ type: 'transfer', amount_paise: 5000, account_id: 'A', transfer_account_id: 'B' });
		expect(balanceDelta(t, 'A')).toBe(-5000);
		expect(balanceDelta(t, 'B')).toBe(5000);
		expect(balanceDelta(t, 'A') + balanceDelta(t, 'B')).toBe(0);
	});
});

describe('balanceFromTransactions', () => {
	it('opening + deltas', () => {
		const txns = [
			txn({ type: 'income', amount_paise: 10000, account_id: 'A' }),
			txn({ type: 'expense', amount_paise: 3000, account_id: 'A' }),
			txn({ type: 'transfer', amount_paise: 2000, account_id: 'A', transfer_account_id: 'B' })
		];
		expect(balanceFromTransactions(100000, txns, 'A')).toBe(105000);
		expect(balanceFromTransactions(0, txns, 'B')).toBe(2000);
	});
});

describe('budgetRollup', () => {
	it('sums expense txns per category vs its budget', () => {
		const cats: Category[] = [
			{ id: 'c1', user_id: 'u', name: 'Food', kind: 'expense', icon: null, color: null, monthly_budget_paise: 500000, created_at: '', updated_at: '' },
			{ id: 'c2', user_id: 'u', name: 'Salary', kind: 'income', icon: null, color: null, monthly_budget_paise: 0, created_at: '', updated_at: '' }
		];
		const txns = [
			txn({ type: 'expense', amount_paise: 120000, category_id: 'c1' }),
			txn({ type: 'expense', amount_paise: 80000, category_id: 'c1' }),
			txn({ type: 'income', amount_paise: 9000000, category_id: 'c2' })
		];
		const lines = budgetRollup(cats, txns);
		expect(lines).toEqual([{ category_id: 'c1', name: 'Food', spent_paise: 200000, budget_paise: 500000 }]);
	});
});

describe('catchUpOccurrences', () => {
	it('returns nothing when next run is in the future', () => {
		expect(catchUpOccurrences('2026-07-01', 'monthly', null, '2026-06-26')).toEqual({ dates: [], nextRunOn: '2026-07-01' });
	});
	it('posts every missed monthly occurrence up to today and advances', () => {
		const r = catchUpOccurrences('2026-04-15', 'monthly', null, '2026-06-26');
		expect(r.dates).toEqual(['2026-04-15', '2026-05-15', '2026-06-15']);
		expect(r.nextRunOn).toBe('2026-07-15');
	});
	it('is idempotent — re-running from the advanced date yields nothing', () => {
		const r2 = catchUpOccurrences('2026-07-15', 'monthly', null, '2026-06-26');
		expect(r2.dates).toEqual([]);
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-calc.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `src/lib/finance/calc.ts`:

```ts
import type { Transaction, Category, Cadence } from './types';
import { advanceDate } from './dates';

export interface BudgetLine {
	category_id: string;
	name: string;
	spent_paise: number;
	budget_paise: number;
}

export function balanceDelta(t: Transaction, accountId: string): number {
	if (t.type === 'income' && t.account_id === accountId) return t.amount_paise;
	if (t.type === 'expense' && t.account_id === accountId) return -t.amount_paise;
	if (t.type === 'transfer') {
		let d = 0;
		if (t.account_id === accountId) d -= t.amount_paise;
		if (t.transfer_account_id === accountId) d += t.amount_paise;
		return d;
	}
	return 0;
}

export function balanceFromTransactions(openingPaise: number, txns: Transaction[], accountId: string): number {
	return txns.reduce((bal, t) => bal + balanceDelta(t, accountId), openingPaise);
}

export function budgetRollup(categories: Category[], monthTxns: Transaction[]): BudgetLine[] {
	return categories
		.filter((c) => c.kind === 'expense')
		.map((c) => ({
			category_id: c.id,
			name: c.name,
			spent_paise: monthTxns
				.filter((t) => t.type === 'expense' && t.category_id === c.id)
				.reduce((sum, t) => sum + t.amount_paise, 0),
			budget_paise: c.monthly_budget_paise
		}));
}

export function catchUpOccurrences(
	nextRunOn: string,
	cadence: Cadence,
	intervalDays: number | null,
	today: string
): { dates: string[]; nextRunOn: string } {
	const dates: string[] = [];
	let cursor = nextRunOn;
	// guard against a misconfigured custom interval looping forever
	let guard = 0;
	while (cursor <= today && guard < 1000) {
		dates.push(cursor);
		cursor = advanceDate(cursor, cadence, intervalDays);
		guard++;
	}
	return { dates, nextRunOn: cursor };
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-calc.test.ts`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add src/lib/finance/calc.ts tests/unit/finance-calc.test.ts
git commit -m "feat(finance): pure money calc — balances, budgets, catch-up"
```

---

## Stage 3 — Domain services

### Task 6: Accounts service — repo, net worth, reconcile

**Files:**
- Create: `src/lib/finance/accounts.ts`
- Test: `tests/unit/finance-accounts.test.ts`

**Interfaces:**
- Consumes: `SupabaseRepository` (`$lib/data/repository`), `balanceFromTransactions` (`./calc`), `Account`/`Transaction` (`./types`).
- Produces:
  - `accountsRepo: SupabaseRepository<Account>`
  - `netWorth(accounts: Account[]): number`
  - `reconcile(account: Account, txns: Transaction[]): { expected: number; drift: number }` (pure)
  - `reconcileAccount(accountId: string): Promise<{ repaired: boolean; balance: number }>`
  - `reconcileAll(): Promise<number>` (returns count repaired)

- [ ] **Step 1: Write the failing test** (covers the pure logic)

Create `tests/unit/finance-accounts.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { netWorth, reconcile } from '$lib/finance/accounts';
import type { Account, Transaction } from '$lib/finance/types';

function acct(p: Partial<Account>): Account {
	return {
		id: 'A', user_id: 'u', name: 'HDFC', type: 'bank', opening_balance_paise: 0,
		balance_paise: 0, currency: 'INR', archived: false, created_at: '', updated_at: '', ...p
	};
}
function txn(p: Partial<Transaction>): Transaction {
	return {
		id: 't', user_id: 'u', account_id: 'A', category_id: null, type: 'expense',
		amount_paise: 0, transfer_account_id: null, note: null, occurred_on: '2026-06-01',
		recurring_id: null, created_at: '', updated_at: '', ...p
	};
}

describe('netWorth', () => {
	it('sums non-archived account balances', () => {
		expect(netWorth([acct({ balance_paise: 100000 }), acct({ balance_paise: 50000 }), acct({ balance_paise: 999, archived: true })])).toBe(150000);
	});
});

describe('reconcile', () => {
	it('reports drift between cached balance and recomputed balance', () => {
		const a = acct({ id: 'A', opening_balance_paise: 100000, balance_paise: 100000 });
		const txns = [txn({ type: 'expense', amount_paise: 3000, account_id: 'A' })];
		expect(reconcile(a, txns)).toEqual({ expected: 97000, drift: -3000 });
	});
	it('zero drift when cache is correct', () => {
		const a = acct({ id: 'A', opening_balance_paise: 100000, balance_paise: 97000 });
		const txns = [txn({ type: 'expense', amount_paise: 3000, account_id: 'A' })];
		expect(reconcile(a, txns)).toEqual({ expected: 97000, drift: 0 });
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-accounts.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `src/lib/finance/accounts.ts`:

```ts
import { SupabaseRepository } from '$lib/data/repository';
import type { Account, Transaction } from './types';
import { balanceFromTransactions } from './calc';
import { forAccountTxns } from './transactions';

export const accountsRepo = new SupabaseRepository<Account>('accounts');

export function netWorth(accounts: Account[]): number {
	return accounts.filter((a) => !a.archived).reduce((s, a) => s + a.balance_paise, 0);
}

export function reconcile(account: Account, txns: Transaction[]): { expected: number; drift: number } {
	const expected = balanceFromTransactions(account.opening_balance_paise, txns, account.id);
	return { expected, drift: expected - account.balance_paise };
}

export async function reconcileAccount(accountId: string): Promise<{ repaired: boolean; balance: number }> {
	const account = await accountsRepo.get(accountId);
	if (!account) return { repaired: false, balance: 0 };
	const txns = await forAccountTxns(accountId);
	const { expected, drift } = reconcile(account, txns);
	if (drift !== 0) {
		await accountsRepo.update(accountId, { balance_paise: expected } as Partial<Account>);
		return { repaired: true, balance: expected };
	}
	return { repaired: false, balance: expected };
}

export async function reconcileAll(): Promise<number> {
	const accounts = await accountsRepo.list();
	let repaired = 0;
	for (const a of accounts) {
		const r = await reconcileAccount(a.id);
		if (r.repaired) repaired++;
	}
	return repaired;
}
```

> Note: `forAccountTxns` is defined in Task 9 (transactions service). `accounts.ts` and `transactions.ts` import from each other, but only inside async function bodies (not at module top level), so there is no circular-initialization problem.

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-accounts.test.ts`
Expected: PASS. (`bun run check` will fail until Task 9 adds `txnRepo.forAccount` — that's expected; do not commit a broken type-check. Reorder: if executing strictly in order, create a temporary stub. Simplest: implement Task 9 immediately after this step, then run `bun run check` once before committing both.)

- [ ] **Step 5: Commit** (after Task 9 so `bun run check` is clean)

```bash
git add src/lib/finance/accounts.ts tests/unit/finance-accounts.test.ts
git commit -m "feat(finance): accounts service — net worth + reconcile"
```

### Task 7: Categories service + default seed

**Files:**
- Create: `src/lib/finance/categories.ts`

**Interfaces:**
- Produces:
  - `categoriesRepo: SupabaseRepository<Category>`
  - `DEFAULT_CATEGORIES: { name: string; kind: CategoryKind; icon: string; color: string }[]`
  - `seedDefaultCategories(): Promise<boolean>` (returns true if it seeded, false if categories already existed)

- [ ] **Step 1: Implement** (no unit test — pure DB orchestration; exercised by dashboard load + e2e)

Create `src/lib/finance/categories.ts`:

```ts
import { SupabaseRepository } from '$lib/data/repository';
import type { Category, CategoryKind } from './types';

export const categoriesRepo = new SupabaseRepository<Category>('categories');

export const DEFAULT_CATEGORIES: { name: string; kind: CategoryKind; icon: string; color: string }[] = [
	{ name: 'Salary', kind: 'income', icon: 'wallet', color: 'oklch(0.72 0.15 150)' },
	{ name: 'Other income', kind: 'income', icon: 'plus', color: 'oklch(0.72 0.12 200)' },
	{ name: 'Groceries', kind: 'expense', icon: 'shopping-cart', color: 'oklch(0.7 0.15 60)' },
	{ name: 'Rent', kind: 'expense', icon: 'home', color: 'oklch(0.65 0.16 25)' },
	{ name: 'Food & dining', kind: 'expense', icon: 'utensils', color: 'oklch(0.7 0.16 40)' },
	{ name: 'Transport', kind: 'expense', icon: 'car', color: 'oklch(0.68 0.14 280)' },
	{ name: 'Bills & utilities', kind: 'expense', icon: 'zap', color: 'oklch(0.7 0.13 100)' },
	{ name: 'Subscriptions', kind: 'expense', icon: 'repeat', color: 'oklch(0.66 0.15 320)' },
	{ name: 'Health', kind: 'expense', icon: 'heart', color: 'oklch(0.68 0.16 10)' },
	{ name: 'Investments', kind: 'expense', icon: 'trending-up', color: 'oklch(0.7 0.14 170)' },
	{ name: 'Shopping', kind: 'expense', icon: 'shopping-bag', color: 'oklch(0.69 0.15 330)' },
	{ name: 'Misc', kind: 'expense', icon: 'circle', color: 'oklch(0.6 0.02 260)' }
];

export async function seedDefaultCategories(): Promise<boolean> {
	const existing = await categoriesRepo.list();
	if (existing.length > 0) return false;
	for (const c of DEFAULT_CATEGORIES) {
		await categoriesRepo.create({ ...c, monthly_budget_paise: 0 } as Partial<Category>);
	}
	return true;
}
```

- [ ] **Step 2: Verify types**

Run: `bun run check`
Expected: 0 errors (after Task 9 lands; see Task 6 note).

- [ ] **Step 3: Commit**

```bash
git add src/lib/finance/categories.ts
git commit -m "feat(finance): categories service + default seed"
```

### Task 8: Budget totals helper

**Files:**
- Create: `src/lib/finance/budgets.ts`
- Test: `tests/unit/finance-calc.test.ts` (append)

**Interfaces:**
- Consumes: `budgetRollup`, `BudgetLine` (`./calc`).
- Produces: `budgetTotals(lines: BudgetLine[]): { spent_paise: number; budget_paise: number }`, and re-exports `budgetRollup`/`BudgetLine` for a single finance entry point.

- [ ] **Step 1: Add the failing test** — append to `tests/unit/finance-calc.test.ts`:

```ts
import { budgetTotals } from '$lib/finance/budgets';

describe('budgetTotals', () => {
	it('sums spent and budget across lines', () => {
		expect(
			budgetTotals([
				{ category_id: 'c1', name: 'Food', spent_paise: 200000, budget_paise: 500000 },
				{ category_id: 'c2', name: 'Rent', spent_paise: 1500000, budget_paise: 1500000 }
			])
		).toEqual({ spent_paise: 1700000, budget_paise: 2000000 });
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-calc.test.ts`
Expected: FAIL — `$lib/finance/budgets` not found.

- [ ] **Step 3: Implement**

Create `src/lib/finance/budgets.ts`:

```ts
import { budgetRollup, type BudgetLine } from './calc';

export { budgetRollup, type BudgetLine };

export function budgetTotals(lines: BudgetLine[]): { spent_paise: number; budget_paise: number } {
	return lines.reduce(
		(acc, l) => ({ spent_paise: acc.spent_paise + l.spent_paise, budget_paise: acc.budget_paise + l.budget_paise }),
		{ spent_paise: 0, budget_paise: 0 }
	);
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-calc.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/finance/budgets.ts tests/unit/finance-calc.test.ts
git commit -m "feat(finance): budget totals helper"
```

---

## Stage 4 — Accounts + Transactions + Quick-add (the core loop)

### Task 9: Transactions service (offline-capable writes + balance application)

**Files:**
- Create: `src/lib/finance/transactions.ts`

**Interfaces:**
- Consumes: `SupabaseRepository`, `supabaseBrowser` (`$lib/supabase/client`), `enqueue` (`$lib/data/sync-queue`), `balanceDelta` (`./calc`), `monthRange` + `todayIso` (`./dates`), `accountsRepo` (`./accounts`), `Account`/`Transaction` (`./types`).
- Produces:
  - `txnRepo: SupabaseRepository<Transaction>`
  - `forAccountTxns(accountId: string): Promise<Transaction[]>`
  - `listByMonth(monthKey: string): Promise<Transaction[]>` (monthKey `'YYYY-MM'`)
  - `createTransaction(input: NewTransaction): Promise<Transaction>` where `NewTransaction = { account_id: string; type: TxnType; amount_paise: number; category_id?: string | null; transfer_account_id?: string | null; note?: string | null; occurred_on?: string; recurring_id?: string | null }`
  - `updateTransaction(prev: Transaction, patch: Partial<Transaction>): Promise<Transaction>`
  - `deleteTransaction(t: Transaction): Promise<void>`

- [ ] **Step 1: Implement** (logic is exercised by the calc tests + Playwright in Stage 7; the impure glue here is thin)

Create `src/lib/finance/transactions.ts`:

```ts
import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import { enqueue } from '$lib/data/sync-queue';
import { balanceDelta } from './calc';
import { monthRange, todayIso } from './dates';
import type { Account, Transaction, TxnType } from './types';

export const txnRepo = new SupabaseRepository<Transaction>('transactions');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export interface NewTransaction {
	account_id: string;
	type: TxnType;
	amount_paise: number;
	category_id?: string | null;
	transfer_account_id?: string | null;
	note?: string | null;
	occurred_on?: string;
	recurring_id?: string | null;
}

export async function forAccountTxns(accountId: string): Promise<Transaction[]> {
	const { data, error } = await db()
		.from('transactions')
		.select('*')
		.or(`account_id.eq.${accountId},transfer_account_id.eq.${accountId}`);
	if (error) throw error;
	return (data ?? []) as Transaction[];
}

export async function listByMonth(monthKey: string): Promise<Transaction[]> {
	const [year, month] = monthKey.split('-').map(Number);
	const { start, end } = monthRange(year, month);
	const { data, error } = await db()
		.from('transactions')
		.select('*')
		.gte('occurred_on', start)
		.lte('occurred_on', end)
		.order('occurred_on', { ascending: false });
	if (error) throw error;
	return (data ?? []) as Transaction[];
}

// Import accountsRepo lazily-at-call-time to avoid top-level circular init.
async function applyToBalances(t: Transaction, sign: 1 | -1): Promise<void> {
	const { accountsRepo } = await import('./accounts');
	const ids = [t.account_id, t.transfer_account_id].filter(Boolean) as string[];
	for (const id of ids) {
		const acc = await accountsRepo.get(id);
		if (!acc) continue;
		const delta = balanceDelta(t, id) * sign;
		await accountsRepo.update(id, { balance_paise: acc.balance_paise + delta } as Partial<Account>);
	}
}

export async function createTransaction(input: NewTransaction): Promise<Transaction> {
	const row = {
		id: crypto.randomUUID(),
		account_id: input.account_id,
		category_id: input.category_id ?? null,
		type: input.type,
		amount_paise: input.amount_paise,
		transfer_account_id: input.transfer_account_id ?? null,
		note: input.note ?? null,
		occurred_on: input.occurred_on ?? todayIso(),
		recurring_id: input.recurring_id ?? null
	};
	if (navigator.onLine) {
		const created = await txnRepo.create(row as Partial<Transaction>);
		await applyToBalances(created, 1);
		return created;
	}
	// Offline: queue the insert; reconcileAll() on next online open repairs balances.
	await enqueue({ table: 'transactions', op: 'create', payload: { data: row }, createdAt: Date.now() });
	return row as Transaction;
}

export async function updateTransaction(prev: Transaction, patch: Partial<Transaction>): Promise<Transaction> {
	const next = { ...prev, ...patch };
	if (navigator.onLine) {
		await applyToBalances(prev, -1);
		const updated = await txnRepo.update(prev.id, patch);
		await applyToBalances(updated, 1);
		return updated;
	}
	await enqueue({ table: 'transactions', op: 'update', payload: { id: prev.id, data: patch as Record<string, unknown> }, createdAt: Date.now() });
	return next;
}

export async function deleteTransaction(t: Transaction): Promise<void> {
	if (navigator.onLine) {
		await applyToBalances(t, -1);
		await txnRepo.remove(t.id);
		return;
	}
	await enqueue({ table: 'transactions', op: 'remove', payload: { id: t.id }, createdAt: Date.now() });
}
```

- [ ] **Step 2: Type-check the whole finance layer** (Tasks 6–9 now complete the import graph)

Run: `bun run check`
Expected: 0 errors.

- [ ] **Step 3: Run the full unit suite**

Run: `bun run test -- --run`
Expected: all PASS (dates, calc, accounts, money).

- [ ] **Step 4: Commit Tasks 6–9 together** (now that `bun run check` is clean)

```bash
git add src/lib/finance/accounts.ts src/lib/finance/categories.ts src/lib/finance/transactions.ts tests/unit/finance-accounts.test.ts
git commit -m "feat(finance): accounts + categories + transactions services"
```

### Task 10: Finance sub-layout (nav + seed + reconcile on mount)

**Files:**
- Create: `src/routes/(app)/finance/+layout.svelte`

**Interfaces:**
- Consumes: `seedDefaultCategories` (`$lib/finance/categories`), `reconcileAll` (`$lib/finance/accounts`).
- Produces: the finance shell; child routes render in the `{@render children()}` slot.

- [ ] **Step 1: Implement**

Create `src/routes/(app)/finance/+layout.svelte`:

```svelte
<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { cn } from '$lib/utils';
	import { seedDefaultCategories } from '$lib/finance/categories';
	import { reconcileAll } from '$lib/finance/accounts';

	let { children } = $props();

	const tabs = [
		{ href: '/finance', label: 'Overview' },
		{ href: '/finance/transactions', label: 'Transactions' },
		{ href: '/finance/accounts', label: 'Accounts' },
		{ href: '/finance/budgets', label: 'Budgets' },
		{ href: '/finance/goals', label: 'Goals' },
		{ href: '/finance/investments', label: 'Investments' }
	];

	onMount(async () => {
		if (!navigator.onLine) return;
		await seedDefaultCategories();
		await reconcileAll();
	});
</script>

<div class="kn-stagger flex flex-col gap-4">
	<nav class="flex flex-wrap gap-1 border-b border-border pb-2">
		{#each tabs as t (t.href)}
			<a
				href={t.href}
				class={cn(
					'rounded-md px-3 py-1.5 text-sm transition-colors',
					page.url.pathname === t.href
						? 'bg-secondary text-secondary-foreground'
						: 'text-muted-foreground hover:bg-secondary/50'
				)}
			>
				{t.label}
			</a>
		{/each}
	</nav>
	{@render children()}
</div>
```

> Catch-up (`runCatchUp`) is added to this `onMount` in Task 19, once the recurring service exists.

- [ ] **Step 2: Verify**

Run: `bun run dev` → visit `http://localhost:5177/finance`. Expected: pill nav renders; no console errors; default categories created once (verify via `bunx supabase studio` or a later Budgets page).

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "src/routes/(app)/finance/+layout.svelte"
git commit -m "feat(finance): sub-nav layout + seed + reconcile on mount"
```

### Task 11: MonthNav + TransactionRow shared components

**Files:**
- Create: `src/lib/components/finance/MonthNav.svelte`
- Create: `src/lib/components/finance/TransactionRow.svelte`

**Interfaces:**
- `MonthNav` props: `{ monthKey: string; onChange: (monthKey: string) => void }`. Renders `‹ June 2026 ›`.
- `TransactionRow` props: `{ txn: Transaction; categoryName?: string; accountName?: string }`. Renders one line: note/category, account, signed amount (income green, expense red).

- [ ] **Step 1: Implement MonthNav**

Create `src/lib/components/finance/MonthNav.svelte`:

```svelte
<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import { monthRange } from '$lib/finance/dates';

	let { monthKey, onChange }: { monthKey: string; onChange: (m: string) => void } = $props();

	const label = $derived(
		new Date(`${monthKey}-01T00:00:00Z`).toLocaleDateString('en-IN', {
			month: 'long',
			year: 'numeric',
			timeZone: 'UTC'
		})
	);

	function shift(delta: number) {
		const [y, m] = monthKey.split('-').map(Number);
		const d = new Date(Date.UTC(y, m - 1 + delta, 1));
		const next = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
		onChange(next);
	}
	// monthRange imported so callers can derive ranges from the same source; referenced to keep the dep explicit.
	void monthRange;
</script>

<div class="flex items-center justify-between">
	<Button variant="ghost" size="sm" onclick={() => shift(-1)} aria-label="Previous month">‹</Button>
	<span class="text-sm font-medium">{label}</span>
	<Button variant="ghost" size="sm" onclick={() => shift(1)} aria-label="Next month">›</Button>
</div>
```

- [ ] **Step 2: Implement TransactionRow**

Create `src/lib/components/finance/TransactionRow.svelte`:

```svelte
<script lang="ts">
	import { formatINR } from '$lib/money';
	import type { Transaction } from '$lib/finance/types';

	let {
		txn,
		categoryName = '',
		accountName = ''
	}: { txn: Transaction; categoryName?: string; accountName?: string } = $props();

	const signed = $derived(txn.type === 'income' ? txn.amount_paise : -txn.amount_paise);
	const tone = $derived(
		txn.type === 'income' ? 'text-emerald-500' : txn.type === 'transfer' ? 'text-muted-foreground' : 'text-rose-500'
	);
</script>

<div class="flex items-center justify-between py-2 text-sm">
	<div class="flex flex-col">
		<span class="font-medium">{txn.note || categoryName || txn.type}</span>
		<span class="text-xs text-muted-foreground">{accountName} · {txn.occurred_on}</span>
	</div>
	<span class={tone}>{txn.type === 'transfer' ? formatINR(txn.amount_paise) : formatINR(signed)}</span>
</div>
```

- [ ] **Step 3: Verify**

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add src/lib/components/finance/MonthNav.svelte src/lib/components/finance/TransactionRow.svelte
git commit -m "feat(finance): MonthNav + TransactionRow components"
```

### Task 12: QuickAdd component (3-second add)

**Files:**
- Create: `src/lib/components/finance/QuickAdd.svelte`
- Modify: `src/routes/(app)/+layout.svelte` (mount the global FAB)

**Interfaces:**
- Consumes: `createTransaction` (`$lib/finance/transactions`), `accountsRepo` (`$lib/finance/accounts`), `categoriesRepo` (`$lib/finance/categories`), `toPaise` (`$lib/money`), Dialog + Button + Input UI.
- Produces: a floating `+` button that opens a dialog: amount → category chip → account → save. On save, calls `createTransaction` and invalidates the `['finance']` query scope.

- [ ] **Step 1: Implement QuickAdd**

Create `src/lib/components/finance/QuickAdd.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Dialog from '$lib/components/ui/dialog';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import { toPaise } from '$lib/money';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import { createTransaction } from '$lib/finance/transactions';
	import type { TxnType } from '$lib/finance/types';

	const qc = useQueryClient();
	let open = $state(false);
	let amount = $state('');
	let type = $state<TxnType>('expense');
	let categoryId = $state<string | null>(null);
	let accountId = $state<string | null>(null);
	let toAccountId = $state<string | null>(null); // transfer destination

	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	const visibleCats = $derived(
		($categories.data ?? []).filter((c) => (type === 'income' ? c.kind === 'income' : c.kind === 'expense'))
	);

	$effect(() => {
		if (!accountId && $accounts.data?.length) accountId = $accounts.data[0].id;
	});

	const save = createMutation(() => ({
		mutationFn: async () => {
			if (!accountId) throw new Error('Pick an account');
			if (type === 'transfer' && (!toAccountId || toAccountId === accountId))
				throw new Error('Pick a different destination account');
			return createTransaction({
				account_id: accountId,
				type,
				amount_paise: toPaise(Number(amount)),
				category_id: type === 'transfer' ? null : categoryId,
				transfer_account_id: type === 'transfer' ? toAccountId : null
			});
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance'] });
			amount = '';
			categoryId = null;
			open = false;
		}
	}));

	const canSave = $derived(
		Number(amount) > 0 && !!accountId && (type !== 'transfer' || (!!toAccountId && toAccountId !== accountId))
	);
</script>

<Button
	class="fixed bottom-6 right-6 z-40 h-14 w-14 rounded-full text-2xl shadow-lg"
	onclick={() => (open = true)}
	aria-label="Quick add transaction"
>
	+
</Button>

<Dialog.Root bind:open>
	<Dialog.Content class="max-w-sm">
		<Dialog.Header>
			<Dialog.Title>Quick add</Dialog.Title>
		</Dialog.Header>

		<div class="flex flex-col gap-3">
			<div class="flex gap-1">
				{#each ['expense', 'income', 'transfer'] as const as t}
					<button
						class={cn('flex-1 rounded-md px-2 py-1.5 text-sm', type === t ? 'bg-secondary' : 'text-muted-foreground')}
						onclick={() => (type = t)}
					>
						{t}
					</button>
				{/each}
			</div>

			<Input type="number" inputmode="decimal" placeholder="0.00" bind:value={amount} class="text-2xl h-14" />

			{#if type !== 'transfer'}
				<div class="flex flex-wrap gap-1">
					{#each visibleCats as c (c.id)}
						<button
							class={cn('rounded-full border px-3 py-1 text-xs', categoryId === c.id ? 'bg-secondary' : 'border-border')}
							onclick={() => (categoryId = c.id)}
						>
							{c.name}
						</button>
					{/each}
				</div>
			{/if}

			<select bind:value={accountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each $accounts.data ?? [] as a (a.id)}
					<option value={a.id}>{type === 'transfer' ? `From: ${a.name}` : a.name}</option>
				{/each}
			</select>

			{#if type === 'transfer'}
				<select bind:value={toAccountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
					<option value={null}>To: pick account…</option>
					{#each ($accounts.data ?? []).filter((a) => a.id !== accountId) as a (a.id)}
						<option value={a.id}>To: {a.name}</option>
					{/each}
				</select>
			{/if}

			<Button disabled={!canSave || $save.isPending} onclick={() => $save.mutate()}>
				{$save.isPending ? 'Saving…' : 'Save'}
			</Button>
		</div>
	</Dialog.Content>
</Dialog.Root>
```

- [ ] **Step 2: Mount the FAB globally** — in `src/routes/(app)/+layout.svelte`, import and render `QuickAdd` once (inside the authed shell, after the main content). Add to the `<script>`: `import QuickAdd from '$lib/components/finance/QuickAdd.svelte';` and place `<QuickAdd />` at the end of the layout markup.

- [ ] **Step 3: Verify manually**

Run: `bun run dev`. Create an account first (Task 13), then open the FAB, enter `199.50`, pick a category + account, Save. Expected: dialog closes; transaction appears on the transactions page; account balance drops by ₹199.50.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add src/lib/components/finance/QuickAdd.svelte "src/routes/(app)/+layout.svelte"
git commit -m "feat(finance): 3-second quick-add FAB"
```

### Task 13: Accounts page (CRUD)

**Files:**
- Create: `src/routes/(app)/finance/accounts/+page.svelte`

**Interfaces:**
- Consumes: `accountsRepo` (`$lib/finance/accounts`), `toPaise`/`formatINR` (`$lib/money`), Card + Button + Input.
- Produces: list of accounts with balances + a create form (name, type, opening balance). New accounts set `balance_paise = opening_balance_paise`.

- [ ] **Step 1: Implement**

Create `src/routes/(app)/finance/accounts/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { Account, AccountType } from '$lib/finance/types';

	const qc = useQueryClient();
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let type = $state<AccountType>('bank');
	let opening = $state('');

	const add = createMutation(() => ({
		mutationFn: () => {
			const paise = toPaise(Number(opening) || 0);
			return accountsRepo.create({
				name,
				type,
				opening_balance_paise: paise,
				balance_paise: paise
			} as Partial<Account>);
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance'] });
			name = '';
			opening = '';
		}
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add account</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name (e.g. HDFC)" bind:value={name} class="w-40" />
			<select bind:value={type} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['bank', 'cash', 'upi', 'credit_card', 'wallet'] as t}
					<option value={t}>{t}</option>
				{/each}
			</select>
			<Input type="number" placeholder="Opening ₹" bind:value={opening} class="w-32" />
			<Button disabled={!name || $add.isPending} onclick={() => $add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each $accounts.data ?? [] as a (a.id)}
			<Card.Root>
				<Card.Header>
					<Card.Title class="text-base">{a.name}</Card.Title>
					<Card.Description>{a.type}</Card.Description>
				</Card.Header>
				<Card.Content>
					<span class="text-xl font-semibold">{formatINR(a.balance_paise)}</span>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
```

- [ ] **Step 2: Verify**

Run: `bun run dev` → `/finance/accounts`. Add "HDFC", bank, opening `40000`. Expected: card shows ₹40,000.00.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "src/routes/(app)/finance/accounts/+page.svelte"
git commit -m "feat(finance): accounts page"
```

### Task 14: Transactions page (list + filter + search)

**Files:**
- Create: `src/routes/(app)/finance/transactions/+page.svelte`

**Interfaces:**
- Consumes: `listByMonth`/`deleteTransaction` (`$lib/finance/transactions`), `accountsRepo`/`categoriesRepo`, `MonthNav`, `TransactionRow`, `monthKey`/`todayIso` (`$lib/finance/dates`).
- Produces: month-scoped transaction list with account/category filter + text search; delete per row.

- [ ] **Step 1: Implement**

Create `src/routes/(app)/finance/transactions/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Input } from '$lib/components/ui/input';
	import { Button } from '$lib/components/ui/button';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import TransactionRow from '$lib/components/finance/TransactionRow.svelte';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { listByMonth, deleteTransaction } from '$lib/finance/transactions';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import type { Transaction } from '$lib/finance/types';

	const qc = useQueryClient();
	let month = $state(monthKey(todayIso()));
	let accountFilter = $state('');
	let search = $state('');

	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	const accName = (id: string) => ($accounts.data ?? []).find((a) => a.id === id)?.name ?? '';
	const catName = (id: string | null) => (id ? ($categories.data ?? []).find((c) => c.id === id)?.name ?? '' : '');

	const filtered = $derived(
		($txns.data ?? []).filter((t) => {
			if (accountFilter && t.account_id !== accountFilter && t.transfer_account_id !== accountFilter) return false;
			if (search && !(`${t.note ?? ''} ${catName(t.category_id)}`.toLowerCase().includes(search.toLowerCase()))) return false;
			return true;
		})
	);

	const del = createMutation(() => ({
		mutationFn: (t: Transaction) => deleteTransaction(t),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance'] })
	}));
</script>

<div class="flex flex-col gap-3">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />
	<div class="flex flex-wrap gap-2">
		<select bind:value={accountFilter} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
			<option value="">All accounts</option>
			{#each $accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
		</select>
		<Input placeholder="Search note/category" bind:value={search} class="w-48" />
	</div>

	<Card.Root>
		<Card.Content class="divide-y divide-border">
			{#each filtered as t (t.id)}
				<div class="flex items-center gap-2">
					<div class="flex-1">
						<TransactionRow txn={t} categoryName={catName(t.category_id)} accountName={accName(t.account_id)} />
					</div>
					<Button variant="ghost" size="sm" onclick={() => $del.mutate(t)} aria-label="Delete">✕</Button>
				</div>
			{:else}
				<p class="py-6 text-center text-sm text-muted-foreground">No transactions this month.</p>
			{/each}
		</Card.Content>
	</Card.Root>
</div>
```

- [ ] **Step 2: Verify**

Run: `bun run dev` → `/finance/transactions`. Add a few via quick-add, switch months, filter by account, search. Expected: list updates; delete restores account balance.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "src/routes/(app)/finance/transactions/+page.svelte"
git commit -m "feat(finance): transactions list + filters"
```

---

## Stage 5 — Categories + Budgets + Dashboard

### Task 15: Chart components (ported SVG)

**Files:**
- Create: `src/lib/components/charts/MiniRingChart.svelte`
- Create: `src/lib/components/charts/DonutChart.svelte`
- Test: `tests/unit/charts.test.ts`

**Interfaces:**
- `MiniRingChart` props: `{ value: number; max: number; size?: number; color?: string; label?: string }`. Renders an SVG ring filled `value/max` (clamped 0–1).
- `DonutChart` props: `{ segments: Segment[]; size?: number }` where `Segment = { label: string; value: number; color: string }`.
- Produces (for unit testing the pure math): `src/lib/components/charts/ring.ts` exporting `ringFraction(value: number, max: number): number` and `donutDashArray(values: number[], circumference: number): { dash: number; gap: number; offset: number }[]`.

- [ ] **Step 1: Write the failing test**

Create `tests/unit/charts.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { ringFraction, donutDashArray } from '$lib/components/charts/ring';

describe('ringFraction', () => {
	it('clamps to 0..1', () => {
		expect(ringFraction(50, 100)).toBe(0.5);
		expect(ringFraction(150, 100)).toBe(1);
		expect(ringFraction(10, 0)).toBe(0);
		expect(ringFraction(-5, 100)).toBe(0);
	});
});

describe('donutDashArray', () => {
	it('produces a dash segment per value, offsets accumulating', () => {
		const segs = donutDashArray([25, 75], 100);
		expect(segs[0]).toEqual({ dash: 25, gap: 75, offset: 0 });
		expect(segs[1]).toEqual({ dash: 75, gap: 25, offset: -25 });
	});
	it('handles all-zero safely', () => {
		expect(donutDashArray([0, 0], 100)).toEqual([
			{ dash: 0, gap: 100, offset: 0 },
			{ dash: 0, gap: 100, offset: 0 }
		]);
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/charts.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the pure math**

Create `src/lib/components/charts/ring.ts`:

```ts
export function ringFraction(value: number, max: number): number {
	if (max <= 0) return 0;
	const f = value / max;
	if (f < 0) return 0;
	if (f > 1) return 1;
	return f;
}

export function donutDashArray(
	values: number[],
	circumference: number
): { dash: number; gap: number; offset: number }[] {
	const total = values.reduce((s, v) => s + v, 0);
	let acc = 0;
	return values.map((v) => {
		const dash = total > 0 ? (v / total) * circumference : 0;
		const seg = { dash, gap: circumference - dash, offset: acc === 0 ? 0 : -acc };
		acc += dash;
		return seg;
	});
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/charts.test.ts`
Expected: PASS.

- [ ] **Step 5: Implement MiniRingChart**

Create `src/lib/components/charts/MiniRingChart.svelte`:

```svelte
<script lang="ts">
	import { ringFraction } from './ring';
	let {
		value,
		max,
		size = 56,
		color = 'oklch(0.72 0.15 150)',
		label = ''
	}: { value: number; max: number; size?: number; color?: string; label?: string } = $props();

	const stroke = 6;
	const r = $derived((size - stroke) / 2);
	const c = $derived(2 * Math.PI * r);
	const frac = $derived(ringFraction(value, max));
	const over = $derived(max > 0 && value > max);
</script>

<div class="flex flex-col items-center gap-1">
	<svg width={size} height={size} viewBox="0 0 {size} {size}">
		<circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--muted)" stroke-width={stroke} />
		<circle
			cx={size / 2}
			cy={size / 2}
			r={r}
			fill="none"
			stroke={over ? 'oklch(0.65 0.16 25)' : color}
			stroke-width={stroke}
			stroke-linecap="round"
			stroke-dasharray="{c * frac} {c * (1 - frac)}"
			stroke-dashoffset={c * 0.25}
			transform="rotate(-90 {size / 2} {size / 2})"
		/>
	</svg>
	{#if label}<span class="text-xs text-muted-foreground">{label}</span>{/if}
</div>
```

- [ ] **Step 6: Implement DonutChart**

Create `src/lib/components/charts/DonutChart.svelte`:

```svelte
<script lang="ts">
	import { donutDashArray } from './ring';
	type Segment = { label: string; value: number; color: string };
	let { segments, size = 160 }: { segments: Segment[]; size?: number } = $props();

	const stroke = 18;
	const r = $derived((size - stroke) / 2);
	const c = $derived(2 * Math.PI * r);
	const dashes = $derived(donutDashArray(segments.map((s) => s.value), c));
</script>

<div class="flex items-center gap-4">
	<svg width={size} height={size} viewBox="0 0 {size} {size}">
		<g transform="rotate(-90 {size / 2} {size / 2})">
			{#each segments as s, i (s.label)}
				<circle
					cx={size / 2}
					cy={size / 2}
					r={r}
					fill="none"
					stroke={s.color}
					stroke-width={stroke}
					stroke-dasharray="{dashes[i].dash} {dashes[i].gap}"
					stroke-dashoffset={dashes[i].offset}
				/>
			{/each}
		</g>
	</svg>
	<ul class="flex flex-col gap-1 text-xs">
		{#each segments as s (s.label)}
			<li class="flex items-center gap-2">
				<span class="inline-block h-2 w-2 rounded-full" style="background:{s.color}"></span>{s.label}
			</li>
		{/each}
	</ul>
</div>
```

- [ ] **Step 7: Type-check + commit**

Run: `bun run check`. Expected: 0 errors.

```bash
git add src/lib/components/charts/
git commit -m "feat(charts): ported MiniRingChart + DonutChart (SVG)"
```

### Task 16: Budgets page (categories + budgets + rings)

**Files:**
- Create: `src/routes/(app)/finance/budgets/+page.svelte`

**Interfaces:**
- Consumes: `categoriesRepo`, `listByMonth`, `budgetRollup` (`$lib/finance/budgets`), `MonthNav`, `MiniRingChart`, `toPaise`/`formatINR`, `monthKey`/`todayIso`.
- Produces: per-expense-category budget editor + a ring of spent vs budget for the selected month; create-category form.

- [ ] **Step 1: Implement**

Create `src/routes/(app)/finance/budgets/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import { toPaise, formatINR } from '$lib/money';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { budgetRollup } from '$lib/finance/budgets';
	import { categoriesRepo } from '$lib/finance/categories';
	import { listByMonth } from '$lib/finance/transactions';
	import type { Category } from '$lib/finance/types';

	const qc = useQueryClient();
	let month = $state(monthKey(todayIso()));
	let newName = $state('');

	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));
	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));

	const lines = $derived(budgetRollup($categories.data ?? [], $txns.data ?? []));

	const setBudget = createMutation(() => ({
		mutationFn: ({ id, rupees }: { id: string; rupees: number }) =>
			categoriesRepo.update(id, { monthly_budget_paise: toPaise(rupees) } as Partial<Category>),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'categories'] })
	}));

	const addCat = createMutation(() => ({
		mutationFn: () => categoriesRepo.create({ name: newName, kind: 'expense', monthly_budget_paise: 0 } as Partial<Category>),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'categories'] });
			newName = '';
		}
	}));
</script>

<div class="flex flex-col gap-4">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />

	<Card.Root>
		<Card.Header><Card.Title>Add category</Card.Title></Card.Header>
		<Card.Content class="flex gap-2">
			<Input placeholder="Category name" bind:value={newName} class="w-48" />
			<Button disabled={!newName || $addCat.isPending} onclick={() => $addCat.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each lines as l (l.category_id)}
			<Card.Root>
				<Card.Content class="flex items-center gap-4 pt-4">
					<MiniRingChart value={l.spent_paise} max={l.budget_paise} />
					<div class="flex flex-1 flex-col gap-1">
						<span class="text-sm font-medium">{l.name}</span>
						<span class="text-xs text-muted-foreground">
							{formatINR(l.spent_paise)} / {formatINR(l.budget_paise)}
						</span>
						<Input
							type="number"
							placeholder="Monthly budget ₹"
							class="h-7 w-32 text-xs"
							onchange={(e) => $setBudget.mutate({ id: l.category_id, rupees: Number((e.currentTarget as HTMLInputElement).value) })}
						/>
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
```

- [ ] **Step 2: Verify**

Run: `bun run dev` → `/finance/budgets`. Set a budget, add expenses via quick-add. Expected: ring fills with spend; turns red when over budget.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "src/routes/(app)/finance/budgets/+page.svelte"
git commit -m "feat(finance): budgets page with rings"
```

### Task 17: Finance dashboard

**Files:**
- Create: `src/routes/(app)/finance/+page.svelte`

**Interfaces:**
- Consumes: `accountsRepo`/`netWorth`, `categoriesRepo`, `listByMonth`, `budgetRollup`/`budgetTotals`, `MonthNav`, `MiniRingChart`, `DonutChart`, `TransactionRow`, `formatINR`, `monthKey`/`todayIso`.
- Produces: the overview — net worth, month income/expense, budget ring, spend-by-category donut, account balances, recent transactions. (Recurring/SIP summary card is added in Task 19.)

- [ ] **Step 1: Implement**

Create `src/routes/(app)/finance/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import MonthNav from '$lib/components/finance/MonthNav.svelte';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import DonutChart from '$lib/components/charts/DonutChart.svelte';
	import TransactionRow from '$lib/components/finance/TransactionRow.svelte';
	import { formatINR } from '$lib/money';
	import { monthKey, todayIso } from '$lib/finance/dates';
	import { accountsRepo, netWorth } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import { listByMonth } from '$lib/finance/transactions';
	import { budgetRollup, budgetTotals } from '$lib/finance/budgets';

	let month = $state(monthKey(todayIso()));

	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));
	const txns = createQuery(() => ({ queryKey: ['finance', 'txns', month], queryFn: () => listByMonth(month) }));

	const income = $derived(($txns.data ?? []).filter((t) => t.type === 'income').reduce((s, t) => s + t.amount_paise, 0));
	const expense = $derived(($txns.data ?? []).filter((t) => t.type === 'expense').reduce((s, t) => s + t.amount_paise, 0));
	const lines = $derived(budgetRollup($categories.data ?? [], $txns.data ?? []));
	const totals = $derived(budgetTotals(lines));
	const accName = (id: string) => ($accounts.data ?? []).find((a) => a.id === id)?.name ?? '';
	const catName = (id: string | null) => (id ? ($categories.data ?? []).find((c) => c.id === id)?.name ?? '' : '');

	const donut = $derived(
		lines
			.filter((l) => l.spent_paise > 0)
			.map((l) => ({
				label: l.name,
				value: l.spent_paise,
				color: ($categories.data ?? []).find((c) => c.id === l.category_id)?.color ?? 'oklch(0.6 0.02 260)'
			}))
	);
	const recent = $derived(($txns.data ?? []).slice(0, 8));
</script>

<div class="kn-stagger flex flex-col gap-4">
	<MonthNav monthKey={month} onChange={(m) => (month = m)} />

	<div class="grid gap-3 sm:grid-cols-3">
		<Card.Root><Card.Header><Card.Description>Net worth</Card.Description><Card.Title class="text-2xl">{formatINR(netWorth($accounts.data ?? []))}</Card.Title></Card.Header></Card.Root>
		<Card.Root><Card.Header><Card.Description>Income</Card.Description><Card.Title class="text-2xl text-emerald-500">{formatINR(income)}</Card.Title></Card.Header></Card.Root>
		<Card.Root><Card.Header><Card.Description>Expense</Card.Description><Card.Title class="text-2xl text-rose-500">{formatINR(expense)}</Card.Title></Card.Header></Card.Root>
	</div>

	<div class="grid gap-3 sm:grid-cols-2">
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Budget</Card.Title></Card.Header>
			<Card.Content class="flex items-center gap-4">
				<MiniRingChart value={totals.spent_paise} max={totals.budget_paise} size={88} />
				<span class="text-sm text-muted-foreground">{formatINR(totals.spent_paise)} / {formatINR(totals.budget_paise)}</span>
			</Card.Content>
		</Card.Root>
		<Card.Root>
			<Card.Header><Card.Title class="text-base">Spend by category</Card.Title></Card.Header>
			<Card.Content>
				{#if donut.length}<DonutChart segments={donut} />{:else}<p class="text-sm text-muted-foreground">No spend yet.</p>{/if}
			</Card.Content>
		</Card.Root>
	</div>

	<Card.Root>
		<Card.Header><Card.Title class="text-base">Accounts</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap gap-4">
			{#each $accounts.data ?? [] as a (a.id)}
				<div class="flex flex-col"><span class="text-xs text-muted-foreground">{a.name}</span><span class="font-semibold">{formatINR(a.balance_paise)}</span></div>
			{/each}
		</Card.Content>
	</Card.Root>

	<Card.Root>
		<Card.Header><Card.Title class="text-base">Recent</Card.Title></Card.Header>
		<Card.Content class="divide-y divide-border">
			{#each recent as t (t.id)}
				<TransactionRow txn={t} categoryName={catName(t.category_id)} accountName={accName(t.account_id)} />
			{:else}
				<p class="py-4 text-center text-sm text-muted-foreground">Nothing logged this month.</p>
			{/each}
		</Card.Content>
	</Card.Root>
</div>
```

- [ ] **Step 2: Verify**

Run: `bun run dev` → `/finance`. Expected: net worth, income/expense, budget ring, donut, account balances, recent list all render and update when you quick-add.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add "src/routes/(app)/finance/+page.svelte"
git commit -m "feat(finance): dashboard overview"
```

---

## Stage 6 — Recurring + Subscriptions + catch-up

### Task 18: Recurring service (catch-up engine)

**Files:**
- Create: `src/lib/finance/recurring.ts`
- Test: `tests/unit/finance-recurring.test.ts`

**Interfaces:**
- Consumes: `SupabaseRepository`, `supabaseBrowser`, `catchUpOccurrences` (`./calc`), `todayIso` (`./dates`), `createTransaction` (`./transactions`), `investmentsRepo` (`./investments`), `Recurring`/`TxnType` (`./types`).
- Produces:
  - `recurringRepo: SupabaseRepository<Recurring>`
  - `pendingDates(dates: string[], existing: string[]): string[]` (pure)
  - `runCatchUp(today?: string): Promise<number>` (returns transactions posted)
  - `listActiveSorted(): Promise<Recurring[]>` (active items, soonest `next_run_on` first)

- [ ] **Step 1: Write the failing test**

Create `tests/unit/finance-recurring.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { pendingDates } from '$lib/finance/recurring';

describe('pendingDates', () => {
	it('drops dates already posted for this recurring item', () => {
		expect(pendingDates(['2026-04-15', '2026-05-15', '2026-06-15'], ['2026-04-15'])).toEqual([
			'2026-05-15',
			'2026-06-15'
		]);
	});
	it('returns all when nothing posted', () => {
		expect(pendingDates(['2026-06-15'], [])).toEqual(['2026-06-15']);
	});
	it('returns none when all posted', () => {
		expect(pendingDates(['2026-06-15'], ['2026-06-15'])).toEqual([]);
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-recurring.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Create `src/lib/finance/recurring.ts`:

```ts
import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import { catchUpOccurrences } from './calc';
import { todayIso } from './dates';
import { createTransaction } from './transactions';
import type { Recurring, TxnType } from './types';

export const recurringRepo = new SupabaseRepository<Recurring>('recurring');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export function pendingDates(dates: string[], existing: string[]): string[] {
	const seen = new Set(existing);
	return dates.filter((d) => !seen.has(d));
}

async function existingDatesFor(recurringId: string): Promise<string[]> {
	const { data, error } = await db().from('transactions').select('occurred_on').eq('recurring_id', recurringId);
	if (error) throw error;
	return (data ?? []).map((r: { occurred_on: string }) => r.occurred_on);
}

export async function listActiveSorted(): Promise<Recurring[]> {
	const items = await recurringRepo.list();
	return items.filter((r) => r.active).sort((a, b) => a.next_run_on.localeCompare(b.next_run_on));
}

export async function runCatchUp(today: string = todayIso()): Promise<number> {
	const items = await recurringRepo.list();
	let posted = 0;
	for (const r of items) {
		if (!r.active) continue;
		const { dates, nextRunOn } = catchUpOccurrences(r.next_run_on, r.cadence, r.interval_days, today);
		if (!dates.length) continue;
		const existing = await existingDatesFor(r.id);
		const toPost = pendingDates(dates, existing);
		const txnType: TxnType = r.kind === 'income' ? 'income' : 'expense';
		for (const d of toPost) {
			await createTransaction({
				account_id: r.account_id,
				type: txnType,
				amount_paise: r.amount_paise,
				category_id: r.category_id,
				note: r.name,
				occurred_on: d,
				recurring_id: r.id
			});
			if (r.investment_id) {
				const { investmentsRepo } = await import('./investments');
				const inv = await investmentsRepo.get(r.investment_id);
				if (inv) await investmentsRepo.update(r.investment_id, { invested_paise: inv.invested_paise + r.amount_paise });
			}
			posted++;
		}
		await recurringRepo.update(r.id, { next_run_on: nextRunOn });
	}
	return posted;
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-recurring.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/finance/recurring.ts tests/unit/finance-recurring.test.ts
git commit -m "feat(finance): recurring catch-up engine"
```

### Task 19: Recurring page + wire catch-up + dashboard upcoming card

**Files:**
- Create: `src/routes/(app)/finance/recurring/+page.svelte`
- Modify: `src/routes/(app)/finance/+layout.svelte` (run catch-up on mount + add the nav tab)
- Modify: `src/routes/(app)/finance/+page.svelte` (upcoming card)

**Interfaces:**
- Consumes: `recurringRepo`/`runCatchUp`/`listActiveSorted`, `accountsRepo`, `categoriesRepo`, `toPaise`/`formatINR`, `todayIso`.
- Produces: create/list recurring items (income, expense, subscription); subscriptions show vendor/plan.

- [ ] **Step 1: Add the nav tab + catch-up** — in `src/routes/(app)/finance/+layout.svelte`:

Add to the `tabs` array (after Transactions): `{ href: '/finance/recurring', label: 'Recurring' },`

Extend the imports: `import { reconcileAll } from '$lib/finance/accounts';` → also `import { runCatchUp } from '$lib/finance/recurring';`

Update `onMount` body to:

```ts
	onMount(async () => {
		if (!navigator.onLine) return;
		await seedDefaultCategories();
		await runCatchUp();
		await reconcileAll();
	});
```

- [ ] **Step 2: Implement the recurring page**

Create `src/routes/(app)/finance/recurring/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { todayIso } from '$lib/finance/dates';
	import { recurringRepo, listActiveSorted } from '$lib/finance/recurring';
	import { accountsRepo } from '$lib/finance/accounts';
	import { categoriesRepo } from '$lib/finance/categories';
	import type { Recurring, RecurringKind, Cadence } from '$lib/finance/types';

	const qc = useQueryClient();
	const items = createQuery(() => ({ queryKey: ['finance', 'recurring'], queryFn: () => listActiveSorted() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));
	const categories = createQuery(() => ({ queryKey: ['finance', 'categories'], queryFn: () => categoriesRepo.list() }));

	let kind = $state<RecurringKind>('expense');
	let name = $state('');
	let amount = $state('');
	let cadence = $state<Cadence>('monthly');
	let nextRunOn = $state(todayIso());
	let accountId = $state<string | null>(null);
	let categoryId = $state<string | null>(null);

	$effect(() => {
		if (!accountId && $accounts.data?.length) accountId = $accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: () => {
			if (!accountId) throw new Error('Pick an account');
			return recurringRepo.create({
				kind,
				name,
				amount_paise: toPaise(Number(amount)),
				account_id: accountId,
				category_id: categoryId,
				cadence,
				interval_days: cadence === 'custom' ? 30 : null,
				next_run_on: nextRunOn,
				active: true
			} as Partial<Recurring>);
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'recurring'] });
			name = '';
			amount = '';
		}
	}));

	const toggle = createMutation(() => ({
		mutationFn: (r: Recurring) => recurringRepo.update(r.id, { active: !r.active } as Partial<Recurring>),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'recurring'] })
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add recurring</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<select bind:value={kind} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['income', 'expense', 'subscription'] as k}<option value={k}>{k}</option>{/each}
			</select>
			<Input placeholder="Name (e.g. Salary)" bind:value={name} class="w-40" />
			<Input type="number" placeholder="₹" bind:value={amount} class="w-28" />
			<select bind:value={cadence} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['monthly', 'weekly', 'custom'] as c}<option value={c}>{c}</option>{/each}
			</select>
			<Input type="date" bind:value={nextRunOn} class="w-40" />
			<select bind:value={accountId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each $accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
			</select>
			<select bind:value={categoryId} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				<option value={null}>No category</option>
				{#each $categories.data ?? [] as c (c.id)}<option value={c.id}>{c.name}</option>{/each}
			</select>
			<Button disabled={!name || !(Number(amount) > 0) || $add.isPending} onclick={() => $add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger flex flex-col gap-2">
		{#each $items.data ?? [] as r (r.id)}
			<Card.Root>
				<Card.Content class="flex items-center justify-between pt-4 text-sm">
					<div class="flex flex-col">
						<span class="font-medium">{r.name} <span class="text-xs text-muted-foreground">({r.kind})</span></span>
						<span class="text-xs text-muted-foreground">{formatINR(r.amount_paise)} · {r.cadence} · next {r.next_run_on}</span>
					</div>
					<Button variant="ghost" size="sm" onclick={() => $toggle.mutate(r)}>{r.active ? 'Pause' : 'Resume'}</Button>
				</Card.Content>
			</Card.Root>
		{:else}
			<p class="py-6 text-center text-sm text-muted-foreground">No recurring items yet.</p>
		{/each}
	</div>
</div>
```

> Note: `kind: 'subscription'` posts like an expense and is tracked fully. The optional metadata columns `vendor`, `plan`, `renews_on` exist in the schema (Task 1) but are intentionally not collected in this MVP form — add inputs later if you want richer subscription detail.

- [ ] **Step 3: Add the upcoming card to the dashboard** — in `src/routes/(app)/finance/+page.svelte`:

Add import: `import { listActiveSorted } from '$lib/finance/recurring';`
Add query: `const recurring = createQuery(() => ({ queryKey: ['finance', 'recurring'], queryFn: () => listActiveSorted() }));`
Add this card before the closing `</div>`:

```svelte
	<Card.Root>
		<Card.Header><Card.Title class="text-base">Upcoming</Card.Title></Card.Header>
		<Card.Content class="divide-y divide-border">
			{#each ($recurring.data ?? []).slice(0, 5) as r (r.id)}
				<div class="flex items-center justify-between py-2 text-sm">
					<span>{r.name} <span class="text-xs text-muted-foreground">· {r.next_run_on}</span></span>
					<span class={r.kind === 'income' ? 'text-emerald-500' : 'text-rose-500'}>{formatINR(r.amount_paise)}</span>
				</div>
			{:else}
				<p class="py-4 text-center text-sm text-muted-foreground">No recurring items.</p>
			{/each}
		</Card.Content>
	</Card.Root>
```

- [ ] **Step 4: Verify**

Run: `bun run dev` → `/finance/recurring`. Add "Salary", income, 80000, monthly, next run = a past date. Reload `/finance` (triggers catch-up). Expected: a salary transaction is posted for the due date(s); re-opening does NOT double-post (idempotent); dashboard Upcoming lists it.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add "src/routes/(app)/finance/recurring/+page.svelte" "src/routes/(app)/finance/+layout.svelte" "src/routes/(app)/finance/+page.svelte"
git commit -m "feat(finance): recurring page + catch-up on app open + upcoming card"
```

---

## Stage 7 — Goals + Investments + offline sync + e2e

### Task 20: Savings goals service + page

**Files:**
- Create: `src/lib/finance/goals.ts`
- Create: `src/routes/(app)/finance/goals/+page.svelte`

**Interfaces:**
- Consumes: `SupabaseRepository`, `createTransaction` (`./transactions`), `SavingsGoal` (`./types`).
- Produces:
  - `goalsRepo: SupabaseRepository<SavingsGoal>`
  - `contributeToGoal(goal: SavingsGoal, amountPaise: number, accountId: string): Promise<void>` — logs an expense from the account and bumps `saved_paise`.

- [ ] **Step 1: Implement the service** (orchestration over already-tested pieces; progress math reuses tested `ringFraction`)

Create `src/lib/finance/goals.ts`:

```ts
import { SupabaseRepository } from '$lib/data/repository';
import { createTransaction } from './transactions';
import type { SavingsGoal } from './types';

export const goalsRepo = new SupabaseRepository<SavingsGoal>('savings_goals');

export async function contributeToGoal(goal: SavingsGoal, amountPaise: number, accountId: string): Promise<void> {
	await createTransaction({
		account_id: accountId,
		type: 'expense',
		amount_paise: amountPaise,
		category_id: null,
		note: `Goal: ${goal.name}`
	});
	await goalsRepo.update(goal.id, { saved_paise: goal.saved_paise + amountPaise } as Partial<SavingsGoal>);
}
```

- [ ] **Step 2: Implement the page**

Create `src/routes/(app)/finance/goals/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import MiniRingChart from '$lib/components/charts/MiniRingChart.svelte';
	import { toPaise, formatINR } from '$lib/money';
	import { goalsRepo, contributeToGoal } from '$lib/finance/goals';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { SavingsGoal } from '$lib/finance/types';

	const qc = useQueryClient();
	const goals = createQuery(() => ({ queryKey: ['finance', 'goals'], queryFn: () => goalsRepo.list() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let target = $state('');
	let contribAccount = $state<string | null>(null);

	$effect(() => {
		if (!contribAccount && $accounts.data?.length) contribAccount = $accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: () =>
			goalsRepo.create({ name, target_paise: toPaise(Number(target)), saved_paise: 0 } as Partial<SavingsGoal>),
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance', 'goals'] });
			name = '';
			target = '';
		}
	}));

	const contribute = createMutation(() => ({
		mutationFn: ({ goal, rupees }: { goal: SavingsGoal; rupees: number }) => {
			if (!contribAccount) throw new Error('Pick an account');
			return contributeToGoal(goal, toPaise(rupees), contribAccount);
		},
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance'] })
	}));
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add goal</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name (e.g. Emergency fund)" bind:value={name} class="w-48" />
			<Input type="number" placeholder="Target ₹" bind:value={target} class="w-32" />
			<select bind:value={contribAccount} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each $accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
			</select>
			<Button disabled={!name || !(Number(target) > 0) || $add.isPending} onclick={() => $add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each $goals.data ?? [] as g (g.id)}
			<Card.Root>
				<Card.Content class="flex items-center gap-4 pt-4">
					<MiniRingChart value={g.saved_paise} max={g.target_paise} color="oklch(0.72 0.12 200)" />
					<div class="flex flex-1 flex-col gap-1">
						<span class="text-sm font-medium">{g.name}</span>
						<span class="text-xs text-muted-foreground">{formatINR(g.saved_paise)} / {formatINR(g.target_paise)}</span>
						<div class="flex gap-1">
							<Input type="number" placeholder="Add ₹" class="h-7 w-24 text-xs" id="contrib-{g.id}" />
							<Button
								size="sm"
								onclick={() => {
									const el = document.getElementById(`contrib-${g.id}`) as HTMLInputElement;
									const rupees = Number(el.value);
									if (rupees > 0) $contribute.mutate({ goal: g, rupees });
									el.value = '';
								}}
							>
								Save
							</Button>
						</div>
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
```

- [ ] **Step 3: Verify**

Run: `bun run dev` → `/finance/goals`. Add a goal, contribute ₹1000. Expected: ring advances; an expense transaction is logged; account balance drops by ₹1000.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add src/lib/finance/goals.ts "src/routes/(app)/finance/goals/+page.svelte"
git commit -m "feat(finance): savings goals + contribute"
```

### Task 21: Investments + SIP

**Files:**
- Create: `src/lib/finance/investments.ts`
- Modify: `src/lib/finance/dates.ts` (add `nextMonthlyOn`)
- Test: `tests/unit/finance-dates.test.ts` (append)
- Create: `src/routes/(app)/finance/investments/+page.svelte`

**Interfaces:**
- Produces:
  - `nextMonthlyOn(day: number, today: string): string` (next date on day-of-month ≥ today, clamped to month length)
  - `investmentsRepo: SupabaseRepository<Investment>`
  - `setCurrentValue(id: string, valuePaise: number): Promise<Investment>`
- Behavior: adding a `sip` investment with `sip_amount`/`sip_day` also creates a linked monthly `recurring` (kind `expense`, `investment_id` set) so catch-up posts contributions and bumps `invested_paise`.

- [ ] **Step 1: Add the failing date test** — append to `tests/unit/finance-dates.test.ts`:

```ts
import { nextMonthlyOn } from '$lib/finance/dates';

describe('nextMonthlyOn', () => {
	it('this month when the day has not passed', () => {
		expect(nextMonthlyOn(15, '2026-06-10')).toBe('2026-06-15');
	});
	it('today when the day is today', () => {
		expect(nextMonthlyOn(10, '2026-06-10')).toBe('2026-06-10');
	});
	it('next month when the day already passed', () => {
		expect(nextMonthlyOn(5, '2026-06-10')).toBe('2026-07-05');
	});
	it('clamps to the month length', () => {
		expect(nextMonthlyOn(31, '2026-02-01')).toBe('2026-02-28');
	});
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bun run test -- --run tests/unit/finance-dates.test.ts`
Expected: FAIL — `nextMonthlyOn` is not exported.

- [ ] **Step 3: Implement `nextMonthlyOn`** — append to `src/lib/finance/dates.ts`:

```ts
function clampDay(year: number, month1: number, day: number): string {
	const last = new Date(Date.UTC(year, month1, 0)).getUTCDate();
	return `${year}-${pad(month1)}-${pad(Math.min(day, last))}`;
}

export function nextMonthlyOn(day: number, today: string): string {
	const [y, m] = today.split('-').map(Number);
	const thisMonth = clampDay(y, m, day);
	if (thisMonth >= today) return thisMonth;
	const nm = new Date(Date.UTC(y, m, 1)); // m is 1-based, so this is the 1st of next month
	return clampDay(nm.getUTCFullYear(), nm.getUTCMonth() + 1, day);
}
```

- [ ] **Step 4: Run it, verify it passes**

Run: `bun run test -- --run tests/unit/finance-dates.test.ts`
Expected: PASS (all, including the 4 new).

- [ ] **Step 5: Implement the investments service**

Create `src/lib/finance/investments.ts`:

```ts
import { SupabaseRepository } from '$lib/data/repository';
import type { Investment } from './types';

export const investmentsRepo = new SupabaseRepository<Investment>('investments');

export async function setCurrentValue(id: string, valuePaise: number): Promise<Investment> {
	return investmentsRepo.update(id, { current_value_paise: valuePaise } as Partial<Investment>);
}
```

- [ ] **Step 6: Implement the page**

Create `src/routes/(app)/finance/investments/+page.svelte`:

```svelte
<script lang="ts">
	import { createQuery, createMutation, useQueryClient } from '@tanstack/svelte-query';
	import * as Card from '$lib/components/ui/card';
	import { Button } from '$lib/components/ui/button';
	import { Input } from '$lib/components/ui/input';
	import { toPaise, formatINR } from '$lib/money';
	import { nextMonthlyOn, todayIso } from '$lib/finance/dates';
	import { investmentsRepo, setCurrentValue } from '$lib/finance/investments';
	import { recurringRepo } from '$lib/finance/recurring';
	import { accountsRepo } from '$lib/finance/accounts';
	import type { Investment, InvestmentType, Recurring } from '$lib/finance/types';

	const qc = useQueryClient();
	const investments = createQuery(() => ({ queryKey: ['finance', 'investments'], queryFn: () => investmentsRepo.list() }));
	const accounts = createQuery(() => ({ queryKey: ['finance', 'accounts'], queryFn: () => accountsRepo.list() }));

	let name = $state('');
	let type = $state<InvestmentType>('sip');
	let invested = $state('');
	let sipAmount = $state('');
	let sipDay = $state('1');
	let sipAccount = $state<string | null>(null);

	$effect(() => {
		if (!sipAccount && $accounts.data?.length) sipAccount = $accounts.data[0].id;
	});

	const add = createMutation(() => ({
		mutationFn: async () => {
			const inv = await investmentsRepo.create({
				name,
				type,
				invested_paise: toPaise(Number(invested) || 0),
				current_value_paise: toPaise(Number(invested) || 0),
				sip_amount_paise: type === 'sip' ? toPaise(Number(sipAmount) || 0) : null,
				sip_day: type === 'sip' ? Number(sipDay) : null
			} as Partial<Investment>);
			// Wire a monthly SIP recurring so catch-up auto-posts contributions.
			if (type === 'sip' && Number(sipAmount) > 0 && sipAccount) {
				await recurringRepo.create({
					kind: 'expense',
					name: `SIP: ${name}`,
					amount_paise: toPaise(Number(sipAmount)),
					account_id: sipAccount,
					category_id: null,
					cadence: 'monthly',
					interval_days: null,
					next_run_on: nextMonthlyOn(Number(sipDay), todayIso()),
					active: true,
					investment_id: inv.id
				} as Partial<Recurring>);
			}
			return inv;
		},
		onSuccess: () => {
			qc.invalidateQueries({ queryKey: ['finance'] });
			name = '';
			invested = '';
			sipAmount = '';
		}
	}));

	const updateValue = createMutation(() => ({
		mutationFn: ({ id, rupees }: { id: string; rupees: number }) => setCurrentValue(id, toPaise(rupees)),
		onSuccess: () => qc.invalidateQueries({ queryKey: ['finance', 'investments'] })
	}));

	const gain = (i: Investment) => i.current_value_paise - i.invested_paise;
</script>

<div class="flex flex-col gap-4">
	<Card.Root>
		<Card.Header><Card.Title>Add investment</Card.Title></Card.Header>
		<Card.Content class="flex flex-wrap items-end gap-2">
			<Input placeholder="Name" bind:value={name} class="w-40" />
			<select bind:value={type} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
				{#each ['sip', 'mutual_fund', 'stock', 'other'] as t}<option value={t}>{t}</option>{/each}
			</select>
			<Input type="number" placeholder="Invested ₹" bind:value={invested} class="w-32" />
			{#if type === 'sip'}
				<Input type="number" placeholder="SIP ₹/mo" bind:value={sipAmount} class="w-28" />
				<Input type="number" placeholder="Day (1-28)" bind:value={sipDay} class="w-24" />
				<select bind:value={sipAccount} class="rounded-md border border-border bg-background px-2 py-1.5 text-sm">
					{#each $accounts.data ?? [] as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
				</select>
			{/if}
			<Button disabled={!name || $add.isPending} onclick={() => $add.mutate()}>Add</Button>
		</Card.Content>
	</Card.Root>

	<div class="kn-stagger grid gap-2 sm:grid-cols-2">
		{#each $investments.data ?? [] as i (i.id)}
			<Card.Root>
				<Card.Header>
					<Card.Title class="text-base">{i.name} <span class="text-xs text-muted-foreground">({i.type})</span></Card.Title>
				</Card.Header>
				<Card.Content class="flex flex-col gap-1 text-sm">
					<span>Invested: {formatINR(i.invested_paise)}</span>
					<span>Current: {formatINR(i.current_value_paise)}
						<span class={gain(i) >= 0 ? 'text-emerald-500' : 'text-rose-500'}>({formatINR(gain(i))})</span>
					</span>
					<div class="flex gap-1">
						<Input type="number" placeholder="Update value ₹" class="h-7 w-32 text-xs"
							onchange={(e) => $updateValue.mutate({ id: i.id, rupees: Number((e.currentTarget as HTMLInputElement).value) })} />
					</div>
				</Card.Content>
			</Card.Root>
		{/each}
	</div>
</div>
```

- [ ] **Step 7: Add the nav tab** — in `src/routes/(app)/finance/+layout.svelte`, the `tabs` array already lists Investments (`/finance/investments`); confirm it is present (added in Task 10). No change needed if so.

- [ ] **Step 8: Verify**

Run: `bun run dev` → `/finance/investments`. Add a SIP (₹5000/mo, day 1). Expected: investment card shows; a `SIP: <name>` recurring appears on `/finance/recurring`; on next app-open catch-up posts the contribution and `invested_paise` grows.

Run: `bun run check`. Expected: 0 errors.

- [ ] **Step 9: Commit**

```bash
git add src/lib/finance/investments.ts src/lib/finance/dates.ts tests/unit/finance-dates.test.ts "src/routes/(app)/finance/investments/+page.svelte"
git commit -m "feat(finance): investments + SIP wired to recurring"
```

### Task 22: Offline flush on reconnect

**Files:**
- Create: `src/lib/finance/sync.ts`
- Modify: `src/routes/(app)/+layout.svelte` (initialise flush + listener)

**Interfaces:**
- Consumes: `flush` (`$lib/data/sync-queue`), all finance repos, `reconcileAll` (`./accounts`).
- Produces:
  - `resolveRepo(table: string): Repository<unknown>`
  - `flushFinance(): Promise<number>` — drains the queue, then `reconcileAll()` to repair any balance drift from offline writes.
  - `initFinanceSync(onDone?: () => void): () => void` — flushes now if online, listens for `online`, returns an unsubscribe.

- [ ] **Step 1: Implement**

Create `src/lib/finance/sync.ts`:

```ts
import type { Repository } from '$lib/data/repository';
import { flush } from '$lib/data/sync-queue';
import { txnRepo } from './transactions';
import { accountsRepo, reconcileAll } from './accounts';
import { categoriesRepo } from './categories';
import { recurringRepo } from './recurring';
import { goalsRepo } from './goals';
import { investmentsRepo } from './investments';

export function resolveRepo(table: string): Repository<unknown> {
	switch (table) {
		case 'transactions': return txnRepo as Repository<unknown>;
		case 'accounts': return accountsRepo as Repository<unknown>;
		case 'categories': return categoriesRepo as Repository<unknown>;
		case 'recurring': return recurringRepo as Repository<unknown>;
		case 'savings_goals': return goalsRepo as Repository<unknown>;
		case 'investments': return investmentsRepo as Repository<unknown>;
		default: throw new Error(`No repo registered for table "${table}"`);
	}
}

export async function flushFinance(): Promise<number> {
	const n = await flush(resolveRepo);
	if (n > 0) await reconcileAll();
	return n;
}

export function initFinanceSync(onDone?: () => void): () => void {
	const run = () => {
		if (navigator.onLine) void flushFinance().then(() => onDone?.());
	};
	run();
	window.addEventListener('online', run);
	return () => window.removeEventListener('online', run);
}
```

- [ ] **Step 2: Wire it into the authed layout** — in `src/routes/(app)/+layout.svelte`:

Add imports:
```ts
	import { onMount } from 'svelte';
	import { useQueryClient } from '@tanstack/svelte-query';
	import { initFinanceSync } from '$lib/finance/sync';
```
Add inside `<script>`:
```ts
	const qc = useQueryClient();
	onMount(() => initFinanceSync(() => qc.invalidateQueries({ queryKey: ['finance'] })));
```
(`onMount` returning the unsubscribe cleans up the listener automatically.)

- [ ] **Step 3: Verify**

Run: `bun run check`. Expected: 0 errors.
Run: `bun run test -- --run`. Expected: all unit tests PASS.

- [ ] **Step 4: Commit**

```bash
git add src/lib/finance/sync.ts "src/routes/(app)/+layout.svelte"
git commit -m "feat(finance): flush offline writes + reconcile on reconnect"
```

### Task 23: Playwright e2e — quick-add + offline-then-sync

**Files:**
- Create: `tests/e2e/finance-quickadd.spec.ts`

**Interfaces:**
- Consumes: the running preview build (`webServer` in `playwright.config.ts`), owner login (`owner@myos.local` / `ChangeMe!myos1`).

- [ ] **Step 1: Write the e2e spec**

Create `tests/e2e/finance-quickadd.spec.ts`:

```ts
import { test, expect, type Page } from '@playwright/test';

async function login(page: Page) {
	await page.goto('/login');
	await page.getByPlaceholder('email').fill('owner@myos.local');
	await page.getByPlaceholder('password').fill('ChangeMe!myos1');
	await page.getByRole('button', { name: 'Sign in' }).click();
	await page.waitForURL((url) => !url.pathname.startsWith('/login'));
}

// Idempotent against the persistent local DB: always ensure at least one account
// exists (quick-add auto-selects the first). Repeated runs just add more — harmless.
async function ensureAccount(page: Page) {
	await page.goto('/finance/accounts');
	await page.getByPlaceholder('Name (e.g. HDFC)').fill('Test Bank');
	await page.getByPlaceholder('Opening ₹').fill('10000');
	await page.getByRole('button', { name: 'Add', exact: true }).click();
	await expect(page.getByText('Test Bank').first()).toBeVisible();
}

test('quick-add logs a transaction and it appears in the list', async ({ page }) => {
	await login(page);
	await ensureAccount(page);

	await page.getByRole('button', { name: 'Quick add transaction' }).click();
	await page.getByPlaceholder('0.00').fill('199.50');
	await page.getByRole('button', { name: 'Save' }).click();

	await page.goto('/finance/transactions');
	await expect(page.getByText('₹199.50').first()).toBeVisible();
});

test('offline quick-add syncs after reconnect', async ({ page, context }) => {
	await login(page);
	await ensureAccount(page);

	await context.setOffline(true);
	await page.getByRole('button', { name: 'Quick add transaction' }).click();
	await page.getByPlaceholder('0.00').fill('42.00');
	await page.getByRole('button', { name: 'Save' }).click();

	await context.setOffline(false);
	// Reload while online → authed layout runs flushFinance() on mount, syncing the queue.
	await page.goto('/finance/transactions');
	await expect(page.getByText('₹42.00').first()).toBeVisible({ timeout: 15_000 });
});
```

- [ ] **Step 2: Run the e2e suite**

Run: `bunx playwright test tests/e2e/finance-quickadd.spec.ts`
Expected: both tests PASS. (Requires the local Supabase stack running and the owner account seeded — see CLAUDE.md / Phase 0 Task 7.)

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/finance-quickadd.spec.ts
git commit -m "test(finance): e2e quick-add + offline-then-sync"
```

---

## Final verification

- [ ] `bun run test -- --run` → all unit suites pass (money, dates, calc, accounts, charts, recurring).
- [ ] RLS: export both `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` from `bunx supabase status -o env`, then `bun run test -- --run tests/unit/finance-rls.test.ts` → pass. (Signup is disabled, so the test creates users via the admin/service_role API.)
- [ ] `bun run check` → 0 errors.
- [ ] `bunx playwright test` → all e2e pass.
- [ ] Manual: create accounts, log expenses/income/transfer, set budgets, add recurring (verify catch-up + idempotency), add a goal + contribute, add a SIP, take the app offline and log a transaction, reconnect and confirm it syncs and balances reconcile.
- [ ] Update `CLAUDE.md` roadmap: mark Phase 1 — Finance ✅. Commit.
