-- Gym programming & progress. Exercise catalog (shared + private, same pattern
-- as food_items). Plans → days (weekly timetable) → planned exercises (targets).
-- Logged sessions → per-set logs (the atomic unit progress is derived from).
-- Weight in grams (weight_g) like health_logs. Progress computed in JS (never stored).

create table exercises (
	id uuid primary key default gen_random_uuid(),
	user_id uuid references auth.users(id) on delete cascade,   -- NULL = shared/global
	name text not null,
	muscle_group text not null,
	equipment text not null default 'barbell',
	parent_exercise_id uuid references exercises(id) on delete set null,  -- variations point at base
	unilateral boolean not null default false,
	created_at timestamptz not null default now()
);
create index exercises_user_idx on exercises (user_id);
create index exercises_muscle_idx on exercises (muscle_group);

create table workout_plans (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	name text not null,
	active boolean not null default true,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index workout_plans_user_idx on workout_plans (user_id);

create table plan_days (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	plan_id uuid not null references workout_plans(id) on delete cascade,
	name text not null,
	weekday int check (weekday between 0 and 6),   -- 0=Sun..6=Sat; NULL = unscheduled
	sort_order int not null default 0,
	created_at timestamptz not null default now()
);
create index plan_days_plan_idx on plan_days (plan_id, sort_order);

create table plan_exercises (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	plan_day_id uuid not null references plan_days(id) on delete cascade,
	exercise_id uuid not null references exercises(id) on delete restrict,
	target_sets int not null default 3,
	target_reps_low int not null default 8,
	target_reps_high int not null default 12,
	target_weight_g int,
	sort_order int not null default 0,
	created_at timestamptz not null default now()
);
create index plan_exercises_day_idx on plan_exercises (plan_day_id, sort_order);

create table workout_sessions (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	plan_day_id uuid references plan_days(id) on delete set null,
	logged_on date not null,
	started_at timestamptz,
	ended_at timestamptz,
	notes text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index workout_sessions_user_idx on workout_sessions (user_id, logged_on desc);

create table session_sets (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	session_id uuid not null references workout_sessions(id) on delete cascade,
	exercise_id uuid not null references exercises(id) on delete restrict,
	set_number int not null,
	reps int not null check (reps >= 0),
	weight_g int not null default 0 check (weight_g >= 0),
	rpe numeric(3, 1) check (rpe between 0 and 10),   -- optional rating scale, 0.5 increments
	created_at timestamptz not null default now()
);
create index session_sets_session_idx on session_sets (session_id);
create index session_sets_exercise_idx on session_sets (user_id, exercise_id, created_at desc);

create trigger workout_plans_set_updated before update on workout_plans for each row execute function set_updated_at();
create trigger workout_sessions_set_updated before update on workout_sessions for each row execute function set_updated_at();

alter table exercises enable row level security;
alter table workout_plans enable row level security;
alter table plan_days enable row level security;
alter table plan_exercises enable row level security;
alter table workout_sessions enable row level security;
alter table session_sets enable row level security;

create policy "read shared or own exercises" on exercises for select using (user_id is null or user_id = auth.uid());
create policy "insert own exercises" on exercises for insert with check (user_id = auth.uid());
create policy "update own exercises" on exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete own exercises" on exercises for delete using (user_id = auth.uid());
grant select, insert, update, delete on table exercises to authenticated;

create policy "own workout_plans" on workout_plans for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own plan_days" on plan_days for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own plan_exercises" on plan_exercises for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own workout_sessions" on workout_sessions for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own session_sets" on session_sets for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table workout_plans, plan_days, plan_exercises, workout_sessions, session_sets to authenticated;

-- ---- Seed: ~15 shared exercises ----
insert into exercises (user_id, name, muscle_group, equipment, unilateral) values
	(null, 'Barbell Bench Press', 'chest', 'barbell', false),
	(null, 'Incline Barbell Bench Press', 'chest', 'barbell', false),
	(null, 'Dumbbell Bench Press', 'chest', 'dumbbell', false),
	(null, 'Barbell Back Squat', 'legs', 'barbell', false),
	(null, 'Leg Press', 'legs', 'machine', false),
	(null, 'Romanian Deadlift', 'legs', 'barbell', false),
	(null, 'Barbell Deadlift', 'back', 'barbell', false),
	(null, 'Pull-up', 'back', 'bodyweight', false),
	(null, 'Barbell Row', 'back', 'barbell', false),
	(null, 'Lat Pulldown', 'back', 'cable', false),
	(null, 'Overhead Press', 'shoulders', 'barbell', false),
	(null, 'Dumbbell Shoulder Press', 'shoulders', 'dumbbell', false),
	(null, 'Dumbbell Bicep Curl', 'arms', 'dumbbell', true),
	(null, 'Tricep Pushdown', 'arms', 'cable', false),
	(null, 'Plank', 'core', 'bodyweight', false);

update exercises set parent_exercise_id = (
	select id from exercises where name = 'Barbell Bench Press' and user_id is null
)
where user_id is null and name in ('Incline Barbell Bench Press', 'Dumbbell Bench Press');
