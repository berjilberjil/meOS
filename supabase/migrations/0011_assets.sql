-- Assets & liabilities with cost-per-day / ROI tracking. Money is integer paise
-- (bigint). Owner-only via RLS. Every derived figure (cost/day, days-to-ROI,
-- daily burn) is computed at render time in src/lib/assets/calc.ts — never stored.

create table assets (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	kind text not null default 'asset' check (kind in ('asset','liability')),
	price_paise bigint not null default 0,            -- asset: one-time price; liability: amount per billing period
	purchase_date date not null default current_date,
	category text not null default 'other',
	billing_period text check (billing_period in ('daily','weekly','monthly','yearly')), -- liabilities only
	end_date date,                                    -- liabilities: EMI/contract end
	expected_lifespan_days int check (expected_lifespan_days > 0),
	target_cost_per_day_paise bigint check (target_cost_per_day_paise > 0),
	salvage_value_paise bigint not null default 0,    -- expected resale; reduces the amount to amortize
	retired_on date,                                  -- sold/binned; frozen and excluded from burn
	notes text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index assets_user_idx on assets (user_id, kind);

-- Single config row per owner: income + the app-wide "cheap" threshold.
create table asset_settings (
	user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
	income_amount_paise bigint not null default 0,
	income_period text not null default 'monthly' check (income_period in ('daily','weekly','monthly','yearly')),
	global_target_cpd_paise bigint not null default 1000, -- ₹10/day default "cheap" threshold
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create trigger assets_set_updated before update on assets for each row execute function set_updated_at();
create trigger asset_settings_set_updated before update on asset_settings for each row execute function set_updated_at();

alter table assets enable row level security;
alter table asset_settings enable row level security;

create policy "own assets" on assets for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own asset_settings" on asset_settings for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on table assets to authenticated;
grant select, insert, update, delete on table asset_settings to authenticated;
