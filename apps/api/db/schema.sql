-- meOS backend schema (Postgres / Supabase)
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

-- Per-user app state. One JSONB document per key (myos.fitness, myos.notes, …).
-- The whole product is built on this table.
create table if not exists app_state (
  user_id    integer not null references users(id) on delete cascade,
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- User-added AI provider keys (Gemini / Anthropic / OpenAI). The secret is stored
-- AES-256-GCM-encrypted (see src/lib/server/secrets.ts) so a DB dump alone can't
-- read it. `masked` is the display form; `models` caches the last fetched model
-- list. Per-feature routing (which key + model for chat/analysis/…) lives in
-- app_state under 'myos.ai.routes'.
create table if not exists ai_credentials (
  id         serial primary key,
  user_id    integer not null references users(id) on delete cascade,
  provider   text not null,
  label      text not null,
  secret     text not null,
  masked     text not null,
  enabled    boolean not null default true,
  models     jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ai_credentials_user_idx on ai_credentials(user_id);

-- Characters of speech synthesised per user per UTC day. This is the hard stop
-- that keeps voice free: the Worker refuses before reaching a billable neuron.
create table if not exists voice_budget (
  user_id    integer not null references users(id) on delete cascade,
  day        text not null,          -- 'YYYY-MM-DD', UTC
  chars      integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

-- Every app install signed into an account. `id` is generated once on the
-- device and kept in UserDefaults, so two Macs never collapse into one row.
-- `name` is what the person typed; `system_name` is the machine name a
-- heartbeat refreshes, kept separately so a rename is never overwritten.
-- Plaintext on purpose: this is account metadata, not vault data, and a
-- device that has not unlocked yet still has to appear in the list.
create table if not exists devices (
  user_id     integer not null references users(id) on delete cascade,
  id          text not null,
  name        text not null,
  system_name text not null,
  platform    text not null,
  kind        text not null,          -- 'mac' or 'iphone'
  app_version text not null default '',
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  primary key (user_id, id)
);
create index if not exists devices_user_seen_idx on devices(user_id, last_seen);
