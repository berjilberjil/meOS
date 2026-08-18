-- To-dos + life Goals. Owner-only via RLS. (Distinct from finance savings_goals.)

create table todos (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	title text not null,
	notes text,
	done boolean not null default false,
	due_on date,
	priority int not null default 0 check (priority between 0 and 3),
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index todos_user_idx on todos (user_id, done, due_on);

create table goals (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	title text not null,
	description text,
	status text not null default 'active' check (status in ('active','done','archived')),
	target_date date,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index goals_user_idx on goals (user_id, status);

create trigger todos_set_updated before update on todos for each row execute function set_updated_at();
create trigger goals_set_updated before update on goals for each row execute function set_updated_at();

alter table todos enable row level security;
alter table goals enable row level security;
create policy "own todos" on todos for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own goals" on goals for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table todos, goals to authenticated;
