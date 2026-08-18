-- Journal schema. Rich text stored as TipTap JSON + a plain-text mirror for search.
-- Media (images/video) reuses media_assets with owner_type = 'journal'.

create table journal_entries (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	title text not null default '',
	body_json jsonb not null default '{}',
	body_text text not null default '',
	mood text,
	occurred_on date not null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index journal_entries_date_idx on journal_entries (user_id, occurred_on desc);

create trigger journal_entries_set_updated before update on journal_entries
	for each row execute function set_updated_at();

alter table journal_entries enable row level security;
create policy "own journal" on journal_entries
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table journal_entries to authenticated;
