-- Streak settings: one row per owner. Streak length, practiced days and frozen
-- days are all computed from journal_entries; this only stores configuration.
create table streak_settings (
	user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
	freezes_total int not null default 3,
	streak_goal int not null default 150,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create trigger streak_settings_set_updated
	before update on streak_settings
	for each row execute function set_updated_at();

alter table streak_settings enable row level security;

create policy "own streak_settings" on streak_settings
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());

grant select, insert, update, delete on table streak_settings to authenticated;
