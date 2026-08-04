-- MyOS backend schema (Postgres / Supabase)
-- Single-user personal app, but modelled multi-user so a future iPhone/iPad
-- client (or a second account) works with zero changes.

create table if not exists users (
  id            serial primary key,
  username      text unique not null,
  password_hash text not null,
  created_at    timestamptz not null default now()
);

create table if not exists sessions (
  token      text primary key,
  user_id    integer not null references users(id) on delete cascade,
  expires_at timestamptz not null
);
create index if not exists sessions_user_idx on sessions(user_id);

-- Per-user app state. One JSONB document per key (myos.finance, myos.journal, …).
-- The whole product is built on this table.
create table if not exists app_state (
  user_id    integer not null references users(id) on delete cascade,
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
