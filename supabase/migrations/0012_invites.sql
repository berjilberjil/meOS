-- Invite-only signup gate. Public signup stays disabled (config.toml
-- enable_signup = false, unchanged). New users are created exclusively via the
-- redeem-invite Edge Function, which validates a code here with service_role
-- (bypassing RLS) and calls the Admin API. Only an authenticated owner can
-- generate/manage invites from the app. Keyed on created_by (not user_id)
-- because an invite belongs to whoever generated it.
create table invites (
	id uuid primary key default gen_random_uuid(),
	code text not null unique,                     -- short human code, compared uppercase
	email text,                                    -- optional: lock invite to one address
	created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
	used_by uuid references auth.users(id) on delete set null,
	used_at timestamptz,
	expires_at timestamptz not null default (now() + interval '14 days'),
	revoked boolean not null default false,
	created_at timestamptz not null default now()
);
create unique index invites_code_uq on invites (code);
create index invites_created_by_idx on invites (created_by);

alter table invites enable row level security;
create policy "own invites" on invites
	for all using (created_by = auth.uid()) with check (created_by = auth.uid());
grant select, insert, update, delete on table invites to authenticated;
