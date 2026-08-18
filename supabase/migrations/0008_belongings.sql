-- Things I own: one-off purchases (gadgets, books, …) with cost, and wardrobe
-- items grouped by clothing category.
create table belongings (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	kind text not null, -- 'purchase' | 'clothing'
	category text not null, -- gadget/book/… or tshirt/shorts/…
	name text not null default '',
	cost_paise bigint, -- nullable (wardrobe items may have no cost)
	qty int not null default 1,
	acquired_on date,
	notes text,
	created_at timestamptz not null default now()
);

create index belongings_user_idx on belongings (user_id, kind, category);

alter table belongings enable row level security;

create policy "own belongings" on belongings
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on table belongings to authenticated;
