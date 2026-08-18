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
