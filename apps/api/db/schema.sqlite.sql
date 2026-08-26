-- MyOS backend schema, D1 / SQLite.
-- Ported from db/schema.sql (Postgres). Single-user personal app, modelled
-- multi-user so nothing has to change if a second account ever appears.
--
-- Timestamps are ISO-8601 UTC TEXT written by the app (see nowISO() in
-- lib/server/db.ts), NOT SQLite's current_timestamp: `YYYY-MM-DD HH:MM:SS`
-- does not sort against `YYYY-MM-DDTHH:MM:SS.sssZ`, and session expiry and the
-- state ETag both depend on that ordering.

create table if not exists users (
  id            integer primary key autoincrement,
  username      text unique not null,
  password_hash text not null,
  created_at    text not null default (datetime('now'))
);

create table if not exists sessions (
  token      text primary key,
  user_id    integer not null references users(id) on delete cascade,
  expires_at text not null
);
create index if not exists sessions_user_idx on sessions(user_id);

-- Per-user app state. One JSON document per key (myos.journal, myos.events, …).
-- The whole product is built on this table. Values are ciphertext envelopes —
-- the server cannot read them.
create table if not exists app_state (
  user_id    integer not null references users(id) on delete cascade,
  key        text not null,
  value      text not null,
  updated_at text not null,
  primary key (user_id, key)
);

-- User-added AI provider keys. `secret` is AES-256-GCM encrypted at rest (see
-- lib/server/secrets.ts) so a database dump alone cannot read it.
create table if not exists ai_credentials (
  id         integer primary key autoincrement,
  user_id    integer not null references users(id) on delete cascade,
  provider   text not null,
  label      text not null,
  secret     text not null,
  masked     text not null,
  enabled    integer not null default 1,
  models     text not null default '[]',
  created_at text not null default (datetime('now')),
  updated_at text not null default (datetime('now'))
);
create index if not exists ai_credentials_user_idx on ai_credentials(user_id);

create table if not exists voice_budget (
  user_id    integer not null references users(id) on delete cascade,
  day        text not null,
  chars      integer not null default 0,
  updated_at text not null,
  primary key (user_id, day)
);

-- Calls made against the SERVER's own AI key, per user per UTC day. Users who
-- configure their own key spend their own quota and never appear here. Two
-- ceilings live in src/lib/server/aiBudget.ts: a per-account share, and the
-- account-wide stop that actually protects the key — because the provider
-- quota belongs to the key, not to a person.
create table if not exists ai_budget (
  user_id    integer not null references users(id) on delete cascade,
  day        text not null,          -- 'YYYY-MM-DD', UTC
  calls      integer not null default 0,
  updated_at text not null,
  primary key (user_id, day)
);
