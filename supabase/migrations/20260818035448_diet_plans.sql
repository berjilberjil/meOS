-- Weekly diet plan. One diet_weeks row per owner per Monday; diet_slots hold
-- the foods in each Mon–Sun × breakfast/lunch/dinner/snack cell. Quantity is a
-- serving count (numeric), same as food_log_entries. Derived kcal/protein stay
-- in JS (src/lib/diet + src/lib/nutrition/calc).

create table diet_weeks (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	week_start date not null,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now(),
	unique (user_id, week_start)
);
create index diet_weeks_user_idx on diet_weeks (user_id, week_start desc);

create table diet_slots (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	week_id uuid not null references diet_weeks(id) on delete cascade,
	weekday int not null check (weekday between 0 and 6), -- 0=Mon … 6=Sun
	meal text not null check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
	food_id uuid not null references food_items(id) on delete restrict,
	quantity numeric(6, 2) not null default 1 check (quantity > 0),
	sort_order int not null default 0,
	created_at timestamptz not null default now()
);
create index diet_slots_week_idx on diet_slots (week_id, weekday, meal, sort_order);
create index diet_slots_user_idx on diet_slots (user_id, week_id);

create trigger diet_weeks_set_updated before update on diet_weeks for each row execute function set_updated_at();

alter table diet_weeks enable row level security;
alter table diet_slots enable row level security;

create policy "own diet weeks" on diet_weeks
	for all to authenticated
	using ((select auth.uid()) = user_id)
	with check ((select auth.uid()) = user_id);

create policy "own diet slots" on diet_slots
	for all to authenticated
	using ((select auth.uid()) = user_id)
	with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on table diet_weeks to authenticated;
grant select, insert, update, delete on table diet_slots to authenticated;

-- Replace every food in one meal in one round-trip so a mid-write failure
-- cannot leave a half-cleared slot. SECURITY INVOKER: RLS still applies.
create or replace function replace_diet_slot(
	p_week_id uuid,
	p_weekday int,
	p_meal text,
	p_foods jsonb
) returns setof diet_slots
language plpgsql
security invoker
set search_path = public
as $$
begin
	if auth.uid() is null then
		raise exception 'not authenticated';
	end if;
	if p_weekday < 0 or p_weekday > 6 then
		raise exception 'weekday must be 0-6';
	end if;
	if p_meal not in ('breakfast', 'lunch', 'dinner', 'snack') then
		raise exception 'invalid meal';
	end if;
	if not exists (
		select 1 from diet_weeks w
		where w.id = p_week_id and w.user_id = auth.uid()
	) then
		raise exception 'week not found';
	end if;

	delete from diet_slots
	where week_id = p_week_id
		and weekday = p_weekday
		and meal = p_meal
		and user_id = auth.uid();

	if p_foods is null or jsonb_typeof(p_foods) <> 'array' or jsonb_array_length(p_foods) = 0 then
		return;
	end if;

	return query
	insert into diet_slots (user_id, week_id, weekday, meal, food_id, quantity, sort_order)
	select
		auth.uid(),
		p_week_id,
		p_weekday,
		p_meal,
		(f->>'food_id')::uuid,
		greatest(coalesce((f->>'quantity')::numeric, 1), 0.01),
		(ord - 1)::int
	from jsonb_array_elements(p_foods) with ordinality as t(f, ord)
	returning *;
end;
$$;

revoke all on function replace_diet_slot(uuid, int, text, jsonb) from public;
grant execute on function replace_diet_slot(uuid, int, text, jsonb) to authenticated;
