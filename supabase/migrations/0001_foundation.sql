-- Foundation schema. Single-owner; every row stamped + guarded by user_id.

create table profile (
	user_id uuid primary key references auth.users(id) on delete cascade,
	display_name text,
	preferences jsonb not null default '{}',
	created_at timestamptz not null default now()
);

create table media_assets (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	owner_type text not null,
	owner_id uuid,
	storage_path text not null,
	mime text not null,
	size_bytes bigint not null default 0,
	width int,
	height int,
	duration_ms int,
	thumbnail_path text,
	created_at timestamptz not null default now()
);
create index media_assets_owner_idx on media_assets (user_id, owner_type, owner_id);

create table links (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	source_type text not null,
	source_id uuid not null,
	relation text not null,
	target_type text not null,
	target_id uuid not null,
	created_at timestamptz not null default now()
);
create index links_source_idx on links (user_id, source_type, source_id);
create index links_target_idx on links (user_id, target_type, target_id);

-- RLS: owner-only on every table.
alter table profile enable row level security;
alter table media_assets enable row level security;
alter table links enable row level security;

create policy "own profile" on profile
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own media" on media_assets
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own links" on links
	for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- PostgREST needs table-level privileges in addition to RLS. Grant to the
-- `authenticated` role only — `anon` gets nothing (single-owner app). RLS still
-- restricts every row to its owner.
grant select, insert, update, delete on table profile, media_assets, links to authenticated;

-- Private storage bucket for all media.
insert into storage.buckets (id, name, public) values ('media', 'media', false)
	on conflict (id) do nothing;

create policy "own files read" on storage.objects
	for select using (bucket_id = 'media' and owner = auth.uid());
create policy "own files write" on storage.objects
	for insert with check (bucket_id = 'media' and owner = auth.uid());
create policy "own files delete" on storage.objects
	for delete using (bucket_id = 'media' and owner = auth.uid());
