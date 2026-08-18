-- Health (daily metrics) + Fitness (workouts). Integer units only (no floats):
-- weight in grams, distance in metres, durations/sleep in minutes, water in ml.

create table health_logs (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	logged_on date not null,
	weight_g int,
	sleep_min int,
	water_ml int,
	mood text,
	notes text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create unique index health_logs_day_uq on health_logs (user_id, logged_on);

create table fitness_logs (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	logged_on date not null,
	activity text not null,
	duration_min int not null default 0,
	calories int,
	distance_m int,
	notes text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index fitness_logs_day_idx on fitness_logs (user_id, logged_on desc);

create trigger health_logs_set_updated before update on health_logs for each row execute function set_updated_at();
create trigger fitness_logs_set_updated before update on fitness_logs for each row execute function set_updated_at();

alter table health_logs enable row level security;
alter table fitness_logs enable row level security;
create policy "own health" on health_logs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own fitness" on fitness_logs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table health_logs, fitness_logs to authenticated;
