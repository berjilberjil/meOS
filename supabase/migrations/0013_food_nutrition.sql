-- Food & nutrition. Shared catalog (food_items with user_id NULL, seeded) plus
-- private custom foods. Full nutrient panel via nutrients + food_nutrient_values.
-- Amounts are integers in each nutrient's own unit (mg/mcg); energy in kcal on
-- food_items. Serving quantity is numeric (a serving COUNT like 1.5, exact
-- decimal, not float). Derived daily totals computed in JS (src/lib/nutrition).

create table nutrients (
	id uuid primary key default gen_random_uuid(),
	key text not null unique,
	label text not null,
	unit text not null check (unit in ('kcal', 'mg', 'mcg', 'g_int')),
	nutrient_group text not null check (nutrient_group in ('macro', 'vitamin', 'mineral', 'other')),
	sort_order int not null default 0
);

create table food_items (
	id uuid primary key default gen_random_uuid(),
	user_id uuid references auth.users(id) on delete cascade,   -- NULL = shared/global (seeded)
	name text not null,
	category text not null default 'other',
	default_serving_label text not null,
	serving_grams int not null check (serving_grams > 0),
	energy_kcal int not null default 0,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index food_items_user_idx on food_items (user_id);
create index food_items_name_idx on food_items using gin (to_tsvector('simple', name));

create table food_nutrient_values (
	food_id uuid not null references food_items(id) on delete cascade,
	nutrient_id uuid not null references nutrients(id) on delete cascade,
	amount int not null check (amount >= 0),   -- integer, in nutrients.unit, per default serving
	primary key (food_id, nutrient_id)
);
create index food_nutrient_values_food_idx on food_nutrient_values (food_id);

create table food_log_entries (
	id uuid primary key default gen_random_uuid(),
	user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
	logged_on date not null,
	food_id uuid not null references food_items(id) on delete restrict,
	quantity numeric(6, 2) not null default 1,     -- servings; exact decimal
	meal text check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
	notes text,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);
create index food_log_entries_day_idx on food_log_entries (user_id, logged_on desc);
create index food_log_entries_food_idx on food_log_entries (food_id);

create table nutrition_goals (
	user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
	energy_kcal int, protein_mg int, carb_mg int, fat_mg int, fiber_mg int,
	created_at timestamptz not null default now(),
	updated_at timestamptz not null default now()
);

create trigger food_items_set_updated before update on food_items for each row execute function set_updated_at();
create trigger food_log_entries_set_updated before update on food_log_entries for each row execute function set_updated_at();
create trigger nutrition_goals_set_updated before update on nutrition_goals for each row execute function set_updated_at();

alter table nutrients enable row level security;
alter table food_items enable row level security;
alter table food_nutrient_values enable row level security;
alter table food_log_entries enable row level security;
alter table nutrition_goals enable row level security;

create policy "read nutrients" on nutrients for select using (true);
grant select on table nutrients to authenticated;

create policy "read shared or own foods" on food_items
	for select using (user_id is null or user_id = auth.uid());
create policy "insert own foods" on food_items for insert with check (user_id = auth.uid());
create policy "update own foods" on food_items for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete own foods" on food_items for delete using (user_id = auth.uid());
grant select, insert, update, delete on table food_items to authenticated;

create policy "read values for visible foods" on food_nutrient_values for select using (
	exists (select 1 from food_items f where f.id = food_nutrient_values.food_id and (f.user_id is null or f.user_id = auth.uid()))
);
create policy "write values for own foods" on food_nutrient_values for all using (
	exists (select 1 from food_items f where f.id = food_nutrient_values.food_id and f.user_id = auth.uid())
) with check (
	exists (select 1 from food_items f where f.id = food_nutrient_values.food_id and f.user_id = auth.uid())
);
grant select, insert, update, delete on table food_nutrient_values to authenticated;

create policy "own food log" on food_log_entries for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own nutrition goals" on nutrition_goals for all using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on table food_log_entries to authenticated;
grant select, insert, update, delete on table nutrition_goals to authenticated;

-- ---- Seed: nutrient panel (energy lives on food_items; 25 rows here) ----
insert into nutrients (key, label, unit, nutrient_group, sort_order) values
	('protein', 'Protein', 'mg', 'macro', 1), ('carb', 'Carbohydrate', 'mg', 'macro', 2),
	('fat', 'Fat', 'mg', 'macro', 3), ('fiber', 'Fiber', 'mg', 'macro', 4),
	('sugar', 'Sugar', 'mg', 'macro', 5), ('saturated_fat', 'Saturated fat', 'mg', 'macro', 6),
	('vitamin_a', 'Vitamin A', 'mcg', 'vitamin', 10), ('vitamin_c', 'Vitamin C', 'mg', 'vitamin', 11),
	('vitamin_d', 'Vitamin D', 'mcg', 'vitamin', 12), ('vitamin_e', 'Vitamin E', 'mg', 'vitamin', 13),
	('vitamin_k', 'Vitamin K', 'mcg', 'vitamin', 14), ('vitamin_b1', 'Thiamin (B1)', 'mg', 'vitamin', 15),
	('vitamin_b2', 'Riboflavin (B2)', 'mg', 'vitamin', 16), ('vitamin_b3', 'Niacin (B3)', 'mg', 'vitamin', 17),
	('vitamin_b6', 'Vitamin B6', 'mg', 'vitamin', 18), ('vitamin_b9', 'Folate (B9)', 'mcg', 'vitamin', 19),
	('vitamin_b12', 'Vitamin B12', 'mcg', 'vitamin', 20), ('calcium', 'Calcium', 'mg', 'mineral', 30),
	('iron', 'Iron', 'mg', 'mineral', 31), ('potassium', 'Potassium', 'mg', 'mineral', 32),
	('sodium', 'Sodium', 'mg', 'mineral', 33), ('magnesium', 'Magnesium', 'mg', 'mineral', 34),
	('zinc', 'Zinc', 'mg', 'mineral', 35), ('phosphorus', 'Phosphorus', 'mg', 'mineral', 36),
	('iodine', 'Iodine', 'mcg', 'mineral', 37), ('selenium', 'Selenium', 'mcg', 'mineral', 38);

-- ---- Seed: 30 Tamil-Nadu/gym foods (macros best-effort estimates) ----
insert into food_items (user_id, name, category, default_serving_label, serving_grams, energy_kcal) values
	(null, 'Chapati / Roti', 'grain', '1 chapati', 40, 120),
	(null, 'Idli', 'grain', '1 idli', 40, 60),
	(null, 'Plain Dosa', 'grain', '1 dosa', 60, 130),
	(null, 'Masala Dosa', 'grain', '1 dosa', 120, 250),
	(null, 'Plain rice (cooked)', 'grain', '1 cup', 150, 200),
	(null, 'Curd rice', 'grain', '1 cup', 200, 250),
	(null, 'Sambar', 'prepared', '1 cup', 200, 120),
	(null, 'Rasam', 'prepared', '1 cup', 200, 60),
	(null, 'Chicken breast, cooked', 'protein', '100 g', 100, 165),
	(null, 'Egg, boiled', 'protein', '1 egg', 50, 78),
	(null, 'Milk, whole', 'dairy', '1 cup', 240, 150),
	(null, 'Curd / yogurt, plain', 'dairy', '1 cup', 200, 120),
	(null, 'Banana', 'fruit', '1 medium', 120, 105),
	(null, 'Peanuts, roasted', 'snack', '30 g', 30, 170),
	(null, 'Chicken biryani', 'prepared', '1 plate', 350, 550),
	(null, 'Parotta', 'grain', '1 parotta', 80, 260),
	(null, 'Upma', 'grain', '1 cup', 200, 230),
	(null, 'Pongal (ven)', 'grain', '1 cup', 200, 270),
	(null, 'Filter coffee', 'beverage', '1 cup', 100, 60),
	(null, 'Dal (toor, cooked)', 'prepared', '1 cup', 200, 190),
	(null, 'Paneer', 'dairy', '100 g', 100, 265),
	(null, 'Oats, cooked', 'grain', '1 cup', 240, 150),
	(null, 'Whey protein scoop', 'protein', '1 scoop', 30, 120),
	(null, 'Sambar vada', 'prepared', '2 vadas', 150, 280),
	(null, 'Pesarattu', 'grain', '1 dosa', 100, 180),
	(null, 'Poori', 'grain', '1 poori', 30, 100),
	(null, 'Kesari', 'snack', '1 serving', 100, 300),
	(null, 'Coconut chutney', 'prepared', '2 tbsp', 30, 70),
	(null, 'Boiled sweet potato', 'vegetable', '100 g', 100, 90),
	(null, 'Almonds', 'snack', '10 nuts', 12, 70);

-- ---- Seed: macro values (protein/carb/fat/fiber) per food, in mg (grams x1000) ----
insert into food_nutrient_values (food_id, nutrient_id, amount)
select f.id, n.id, v.amount
from (values
	('Chapati / Roti','protein',3000),('Chapati / Roti','carb',20000),('Chapati / Roti','fat',3000),('Chapati / Roti','fiber',2000),
	('Idli','protein',2000),('Idli','carb',12000),('Idli','fat',0),('Idli','fiber',1000),
	('Plain Dosa','protein',3000),('Plain Dosa','carb',20000),('Plain Dosa','fat',4000),('Plain Dosa','fiber',1000),
	('Masala Dosa','protein',5000),('Masala Dosa','carb',35000),('Masala Dosa','fat',9000),('Masala Dosa','fiber',2000),
	('Plain rice (cooked)','protein',4000),('Plain rice (cooked)','carb',44000),('Plain rice (cooked)','fat',0),('Plain rice (cooked)','fiber',1000),
	('Curd rice','protein',6000),('Curd rice','carb',40000),('Curd rice','fat',6000),('Curd rice','fiber',1000),
	('Sambar','protein',6000),('Sambar','carb',18000),('Sambar','fat',3000),('Sambar','fiber',4000),
	('Rasam','protein',2000),('Rasam','carb',10000),('Rasam','fat',1000),('Rasam','fiber',1000),
	('Chicken breast, cooked','protein',31000),('Chicken breast, cooked','carb',0),('Chicken breast, cooked','fat',4000),('Chicken breast, cooked','fiber',0),
	('Egg, boiled','protein',6000),('Egg, boiled','carb',1000),('Egg, boiled','fat',5000),('Egg, boiled','fiber',0),
	('Milk, whole','protein',8000),('Milk, whole','carb',12000),('Milk, whole','fat',8000),('Milk, whole','fiber',0),
	('Curd / yogurt, plain','protein',7000),('Curd / yogurt, plain','carb',9000),('Curd / yogurt, plain','fat',6000),('Curd / yogurt, plain','fiber',0),
	('Banana','protein',1000),('Banana','carb',27000),('Banana','fat',0),('Banana','fiber',3000),
	('Peanuts, roasted','protein',7000),('Peanuts, roasted','carb',6000),('Peanuts, roasted','fat',14000),('Peanuts, roasted','fiber',2000),
	('Chicken biryani','protein',25000),('Chicken biryani','carb',65000),('Chicken biryani','fat',20000),('Chicken biryani','fiber',3000),
	('Parotta','protein',5000),('Parotta','carb',35000),('Parotta','fat',11000),('Parotta','fiber',1000),
	('Upma','protein',5000),('Upma','carb',35000),('Upma','fat',8000),('Upma','fiber',3000),
	('Pongal (ven)','protein',6000),('Pongal (ven)','carb',40000),('Pongal (ven)','fat',9000),('Pongal (ven)','fiber',2000),
	('Filter coffee','protein',1000),('Filter coffee','carb',9000),('Filter coffee','fat',2000),('Filter coffee','fiber',0),
	('Dal (toor, cooked)','protein',12000),('Dal (toor, cooked)','carb',30000),('Dal (toor, cooked)','fat',3000),('Dal (toor, cooked)','fiber',6000),
	('Paneer','protein',18000),('Paneer','carb',4000),('Paneer','fat',20000),('Paneer','fiber',0),
	('Oats, cooked','protein',5000),('Oats, cooked','carb',27000),('Oats, cooked','fat',3000),('Oats, cooked','fiber',4000),
	('Whey protein scoop','protein',24000),('Whey protein scoop','carb',3000),('Whey protein scoop','fat',2000),('Whey protein scoop','fiber',1000),
	('Sambar vada','protein',8000),('Sambar vada','carb',32000),('Sambar vada','fat',13000),('Sambar vada','fiber',3000),
	('Pesarattu','protein',8000),('Pesarattu','carb',25000),('Pesarattu','fat',5000),('Pesarattu','fiber',4000),
	('Poori','protein',2000),('Poori','carb',12000),('Poori','fat',5000),('Poori','fiber',1000),
	('Kesari','protein',3000),('Kesari','carb',45000),('Kesari','fat',12000),('Kesari','fiber',0),
	('Coconut chutney','protein',1000),('Coconut chutney','carb',3000),('Coconut chutney','fat',6000),('Coconut chutney','fiber',1000),
	('Boiled sweet potato','protein',2000),('Boiled sweet potato','carb',21000),('Boiled sweet potato','fat',0),('Boiled sweet potato','fiber',3000),
	('Almonds','protein',3000),('Almonds','carb',3000),('Almonds','fat',6000),('Almonds','fiber',1000)
) as v(food_name, nutrient_key, amount)
join food_items f on f.name = v.food_name and f.user_id is null
join nutrients n on n.key = v.nutrient_key;
