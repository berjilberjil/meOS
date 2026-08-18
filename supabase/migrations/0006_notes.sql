-- Notes: rich-text (TipTap JSON) + plain-text mirror for search. Owner-only.

create table notes (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	title text not null default '',
	body_json jsonb not null default '{}',
	body_text text not null default '',
	pinned boolean not null default false,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index notes_user_idx on notes (user_id, pinned desc, updated_at desc);

create trigger notes_set_updated before update on notes for each row execute function set_updated_at();

alter table notes enable row level security;
create policy "own notes" on notes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table notes to authenticated;
