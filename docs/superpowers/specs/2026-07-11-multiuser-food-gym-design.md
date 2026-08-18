# MyOS — Multi-user + Food/Nutrition + Gym Programming — Design Spec

**Date:** 2026-07-11
**Status:** Approved design, pre-implementation
**Build order:** Phase A (multi-user) → Phase B (food) → Phase C (gym)

## Overview

Three related additions to MyOS, an offline-first personal-life-OS (SvelteKit 2 + Svelte 5 runes, Tailwind v4, Supabase Postgres/Auth/Storage, Dexie offline cache, static SPA `ssr=false`, Bun):

1. **Invite-only multi-user** — turn the single-owner app into many independent, fully-private accounts. No shared workspaces/teams; each user's data is invisible to every other user (already enforced by per-user RLS on all 19 existing tables).
2. **Food & nutrition tracking** — a shared Tamil-Nadu/Chennai + gym food catalog with a full vitamin/mineral panel, private custom foods, per-day macro/micro totals vs goals. Log "5 chapatis" → auto-compute nutrients.
3. **Gym programming & progress** — exercise catalog with variations, weekly workout plans/timetables, fast per-set logging, and derived progress (est. 1RM, PRs, volume, muscle-group frequency, streak).

### Locked product decisions
- **Signup = invite-only.** Public signup stays disabled. New accounts created only via a validated invite.
- **Food catalog = shared global (seeded, read-only) + private custom foods.** All food *logs* are private.
- **Nutrition = full panel** (energy + 26 nutrient keys in the `nutrients` table: 6 macro-ish + 11 vitamins + 9 minerals). Macros seeded solid; micros best-effort/nullable, UI-labeled "est."
- **IA = sub-tabs under the existing `/fitness` tab**, no new bottom-nav items.

### Conventions inherited (must follow)
- Every user-owned table: `user_id uuid not null default auth.uid() references auth.users(id) on delete cascade`, policy `for all using (user_id = auth.uid()) with check (user_id = auth.uid())`, `grant ... to authenticated`, no `anon` grants. Shared `set_updated_at()` trigger (from `0002_finance.sql`).
- Integer units only for physical/nutrient/money values (money=paise, weight=grams `weight_g`, distance=metres, durations=minutes). Nutrients stored as integers in each nutrient's declared unit (mg or mcg); energy in integer kcal.
- Derived values are computed at render time in JS (`src/lib/*/calc.ts`), never stored. Mirror `finance/calc.ts`, `assets/calc.ts`.
- Data access via `SupabaseRepository<T>('table')`; offline writes via sync-queue. One-row-per-user settings tables use `user_id` as PK (mirror `asset_settings`, `streak_settings`).
- Latest migration is `0011_assets.sql`; new ones are `0012`, `0013`, `0014`.

---

## Information architecture

All new UI lives under the existing `/fitness` bottom-nav tab (dock is full at 6 slots; `nav.ts` `fitness` item already has `match: ['/fitness','/health']` + a long-press fan menu). Add `src/routes/(app)/fitness/+layout.svelte` publishing sub-tabs via `setHeaderTabs()` (mirror `finance/+layout.svelte`):

```
/fitness            → Today   (existing +page content: weight, photos, combined activity feed of fitness_logs + workout_sessions)
/fitness/food       → Food & nutrition (Phase B)
/fitness/workouts   → Today's workout / session logging (Phase C)
/fitness/plan       → Weekly plan/timetable builder (Phase C)
/fitness/progress   → Progress charts, PRs, streaks (Phase C)
```

Extend the `fitness` fan menu in `nav.ts` (keep to ~5 highest-value actions):
```ts
menu: [
  { label: 'Log food', href: '/fitness/food?add=1' },
  { label: 'Start session', href: '/fitness/workouts?start=1' },
  { label: 'Add workout', href: '/fitness?add=workout' }, // existing free-form fitness_logs
  { label: 'Add photo', href: '/fitness?add=photo' },
  { label: 'Add log', href: '/fitness?add=log' }
]
```

New lib modules mirror `src/lib/finance/` structure: `src/lib/nutrition/` (types, repos, calc) and `src/lib/gym/` (types, repos, progress). Auth/invite code under `src/lib/auth/` or existing auth location.

---

## Phase A — Invite-only multi-user

### A.1 Mechanism — Supabase Edge Function `redeem-invite`
Public signup (`enable_signup`) stays `false` permanently (already is). New users are created **only** by a Supabase Edge Function that validates the invite server-side with the `service_role` key and creates the user via the Admin API. The static SPA never holds a privileged key.

Rejected alternatives: (b) before-user-created auth hook — blocked because `enable_signup=false` closes the signup gateway the hook depends on, and re-enabling it reopens public signup; (c) client-side code check — trivially bypassed since the anon key + REST API are public.

**Edge function:** `supabase/functions/redeem-invite/index.ts` (Deno). Contract:
```ts
// POST /functions/v1/redeem-invite  { code, email, password }
// 200: { ok: true }
// 4xx: { ok: false, error: 'invalid_code'|'expired'|'already_used'|'revoked'|'email_mismatch'|'email_taken'|'weak_password' }
```
Logic: build a `service_role` client (env `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`, auto-injected). Look up invite by `code` (uppercased). Validate in order → specific error. `auth.admin.createUser({ email, password, email_confirm: true })`. On success, `update invites set used_by, used_at`. Include CORS (OPTIONS preflight + `Access-Control-Allow-Origin`). If the invite-update fails after user creation, log and still return `ok:true` (account exists; owner can revoke a soft-orphaned invite).

### A.2 `invites` table — migration `0012_invites.sql`
```sql
create table invites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                     -- short human code, e.g. "BRJL-7F3K", compared uppercase
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
```
`used_by is null` = unused. Redemption runs as `service_role` (bypasses RLS/grants); RLS here only governs the owner's in-app "manage invites" screen. No `anon` grant.

### A.3 Signup UX
New route `src/routes/(auth)/signup/+page.svelte` (same auth layout group as the existing login page). URL `/signup?invite=CODE&email=optional`. Fields: invite code (prefilled, uppercased/trimmed, case-insensitive), email, password (+confirm, client match). Submit → call edge function → on `ok`, `supabase.auth.signInWithPassword()` client-side → redirect to journal/dashboard landing. Error copy mapped from the typed error codes. Sign-in page unchanged; add cross-links ("Have an invite? Sign up" / "Already have an account? Sign in").

**Invite management UI** (owner-facing): thin CRUD over `invites` via `SupabaseRepository<Invite>('invites')` — list (code, computed status, created date), Generate (optional email lock + expiry), Revoke. Creating invite rows needs no edge function (RLS lets any authenticated user insert their own).

### A.4 config.toml
No changes needed. `enable_signup=false` (global) and `enable_anonymous_sign_ins=false` stay off forever — they are what keeps `POST /auth/v1/signup` closed. The edge function uses `auth.admin.createUser` (Admin API), unaffected by that flag. Pre-launch checklist (hosted project, not local config): `supabase functions deploy redeem-invite`; set `site_url`/`additional_redirect_urls` to production origins.

### A.5 Profile onboarding
`profile` table already exists (`user_id` PK, `display_name`, `preferences jsonb`) — no schema change. On first login auto-create a blank profile row with `display_name = email.split('@')[0]` (editable later in settings), no blocking modal. `profile` uses `user_id` as PK (not `id`), so use its existing bespoke accessor (see `getPersonal()` referenced by `fitness/+page.svelte`), not the generic `SupabaseRepository`.

### A.6 Data-safety verification
Every new table follows the flat per-user RLS pattern (except the intentionally-shared catalogs in B/C, which get stricter explicit policies). Extend `tests/unit/rls.test.ts` (existing env-gated `userClient(email)` helper) with: User B cannot read User A's `profile`/`invites` rows; and (Phases B/C) User B cannot read/write User A's private `food_items`/`exercises`, but both can read shared (`user_id is null`) rows and neither can write shared rows.

---

## Phase B — Food & nutrition

### B.1 Data model — migration `0013_food_nutrition.sql`
Normalized nutrient values (chosen over a jsonb column: trivially queryable, mirrors the app's flat-relational + Dexie-sync convention, cleaner per-key typing; seed verbosity solved by generating the VALUES block from the table below).

**Units:** energy = integer kcal (denormalized onto `food_items.energy_kcal` — hot, always-present). All other nutrient amounts = integer in the nutrient's own unit (`mg` or `mcg`, declared per-nutrient because trace micros like vitamin D/B12 would round to 0 in mg). Macros stored as **mg** (e.g. 3 g protein → 3000). Serving `quantity` is `numeric(6,2)` (a serving *count* like "1.5 cups", exact decimal, not float) — the one deliberate non-integer, documented as a code comment; every stored nutrient/weight value stays integer.

```sql
create table nutrients (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,            -- 'protein','vitamin_d','iron'
  label text not null,
  unit text not null check (unit in ('kcal','mg','mcg','g_int')),
  nutrient_group text not null check (nutrient_group in ('macro','vitamin','mineral','other')),
  sort_order int not null default 0
);

create table food_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,  -- NULLABLE, no default: null = shared/global
  name text not null,
  category text not null default 'other',
  default_serving_label text not null,     -- '1 chapati', '1 cup (240ml)', '100 g'
  serving_grams int not null check (serving_grams > 0),
  energy_kcal int not null default 0,       -- per default serving
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index food_items_user_idx on food_items (user_id);
create index food_items_name_idx on food_items using gin (to_tsvector('simple', name));

create table food_nutrient_values (
  food_id uuid not null references food_items(id) on delete cascade,
  nutrient_id uuid not null references nutrients(id) on delete cascade,
  amount int not null check (amount >= 0),  -- integer, in nutrients.unit; PER default serving
  primary key (food_id, nutrient_id)
);
create index food_nutrient_values_food_idx on food_nutrient_values (food_id);

create table food_log_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  logged_on date not null,
  food_id uuid not null references food_items(id) on delete restrict,
  quantity numeric(6,2) not null default 1,     -- servings; exact decimal, not float
  meal text check (meal in ('breakfast','lunch','dinner','snack')),
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
grant select on table nutrients to authenticated;   -- no write grant; migration seeds it

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
```

**RLS guarantee:** a user can read any `food_items` where `user_id is null` (shared) OR `= auth.uid()` (own), never another user's private food; the same cascades through `food_nutrient_values` via the `exists` subquery. No authenticated role can write a `user_id is null` row (every write policy requires `user_id = auth.uid()`), so the seeded catalog is structurally read-only except to migrations.

### B.2 Nutrient panel (26 keys)
`energy` kept on `food_items.energy_kcal` (not in `nutrients`). In `nutrients`: macros — `protein` mg, `carb` mg, `fat` mg, `fiber` mg, `sugar` mg, `saturated_fat` mg. Vitamins — `vitamin_a` mcg, `vitamin_c` mg, `vitamin_d` mcg, `vitamin_e` mg, `vitamin_k` mcg, `vitamin_b1` mg, `vitamin_b2` mg, `vitamin_b3` mg, `vitamin_b6` mg, `vitamin_b9` mcg, `vitamin_b12` mcg. Minerals — `calcium` mg, `iron` mg, `potassium` mg, `sodium` mg, `magnesium` mg, `zinc` mg, `phosphorus` mg, `iodine` mcg, `selenium` mcg.

### B.3 Seed foods (~30, best-effort estimates, macros only; micros null in seed)
Per default serving. Macros shown in grams; stored as mg (×1000).

| Name | Serving | g | kcal | P(g) | C(g) | F(g) | Fib(g) |
|---|---|---|---|---|---|---|---|
| Chapati / Roti | 1 chapati | 40 | 120 | 3 | 20 | 3 | 2 |
| Idli | 1 idli | 40 | 60 | 2 | 12 | 0 | 1 |
| Plain Dosa | 1 dosa | 60 | 130 | 3 | 20 | 4 | 1 |
| Masala Dosa | 1 dosa | 120 | 250 | 5 | 35 | 9 | 2 |
| Plain rice (cooked) | 1 cup | 150 | 200 | 4 | 44 | 0 | 1 |
| Curd rice | 1 cup | 200 | 250 | 6 | 40 | 6 | 1 |
| Sambar | 1 cup | 200 | 120 | 6 | 18 | 3 | 4 |
| Rasam | 1 cup | 200 | 60 | 2 | 10 | 1 | 1 |
| Chicken breast, cooked | 100 g | 100 | 165 | 31 | 0 | 4 | 0 |
| Egg, boiled | 1 egg | 50 | 78 | 6 | 1 | 5 | 0 |
| Milk, whole | 1 cup | 240 | 150 | 8 | 12 | 8 | 0 |
| Curd / yogurt, plain | 1 cup | 200 | 120 | 7 | 9 | 6 | 0 |
| Banana | 1 medium | 120 | 105 | 1 | 27 | 0 | 3 |
| Peanuts, roasted | 30 g | 30 | 170 | 7 | 6 | 14 | 2 |
| Chicken biryani | 1 plate | 350 | 550 | 25 | 65 | 20 | 3 |
| Parotta | 1 parotta | 80 | 260 | 5 | 35 | 11 | 1 |
| Upma | 1 cup | 200 | 230 | 5 | 35 | 8 | 3 |
| Pongal (ven) | 1 cup | 200 | 270 | 6 | 40 | 9 | 2 |
| Filter coffee | 1 cup | 100 | 60 | 1 | 9 | 2 | 0 |
| Dal (toor, cooked) | 1 cup | 200 | 190 | 12 | 30 | 3 | 6 |
| Paneer | 100 g | 100 | 265 | 18 | 4 | 20 | 0 |
| Oats, cooked | 1 cup | 240 | 150 | 5 | 27 | 3 | 4 |
| Whey protein scoop | 1 scoop | 30 | 120 | 24 | 3 | 2 | 1 |
| Sambar vada | 2 vadas | 150 | 280 | 8 | 32 | 13 | 3 |
| Pesarattu | 1 dosa | 100 | 180 | 8 | 25 | 5 | 4 |
| Poori | 1 poori | 30 | 100 | 2 | 12 | 5 | 1 |
| Kesari | 1 serving | 100 | 300 | 3 | 45 | 12 | 0 |
| Coconut chutney | 2 tbsp | 30 | 70 | 1 | 3 | 6 | 1 |
| Boiled sweet potato | 100 g | 100 | 90 | 2 | 21 | 0 | 3 |
| Almonds | 10 nuts | 12 | 70 | 3 | 3 | 6 | 1 |

Seed `food_items` with `user_id` explicit NULL (no `auth.uid()` default in migration context). Generate the ~120-row `food_nutrient_values` VALUES block mechanically from this table, joined by name+key.

### B.4 Computation (JS, `src/lib/nutrition/calc.ts`, never stored)
Load `nutrients` + shared `food_items` + own custom foods once per session into memory (TanStack Query, long staleTime). For each `food_log_entry`: multiply the food's per-serving amounts by `quantity` (already per default serving — no gram conversion), summing per day. Pull `protein/carb/fat/fiber` into named fields for rings/bars; keep the rest in a generic `micros: Record<key, amount>` map. v1: `quantity` is always "# of default servings" (for grams, use/create a 100 g food). Round with `Math.round` at the boundary; parse `numeric` `quantity` string once.

### B.5 Food UX (mobile-first, `/fitness/food`)
1. **Today totals card:** calories ring `1,340 / 2,200 kcal` (goal from `nutrition_goals`; raw total if unset) + protein/carb/fat bars; tap → fiber + full-micros detail sheet (consumed amounts; no RDA targets in v1).
2. **Quick-add:** search input filters in-memory catalog (prefix/fuzzy) → tappable results; tap → bottom sheet with quantity stepper (default 1), meal picker (defaults by time-of-day), Add. 2 taps default. When search empty, show **recent foods** (last ~10 distinct logged, one-tap re-log).
3. **Today's log:** grouped by meal, rows `5× Chapati — 600 kcal`, tap-to-edit/swipe-delete.
4. **Add custom food:** name, category, serving label, serving grams, kcal + 4 macros (g→mg on submit); creates `food_items` with `user_id = auth.uid()`. Micros optional/later.

---

## Phase C — Gym programming & progress

### C.1 Data model — migration `0014_gym.sql`
```sql
create table exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,   -- NULL = shared/global
  name text not null,
  muscle_group text not null,   -- chest/back/legs/shoulders/arms/core/full_body/cardio
  equipment text not null default 'barbell',
  parent_exercise_id uuid references exercises(id) on delete set null,  -- variations point at base movement
  unilateral boolean not null default false,
  created_at timestamptz not null default now()
);
create index exercises_user_idx on exercises (user_id);
create index exercises_muscle_idx on exercises (muscle_group);

create table workout_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index workout_plans_user_idx on workout_plans (user_id);

create table plan_days (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  plan_id uuid not null references workout_plans(id) on delete cascade,
  name text not null,
  weekday int check (weekday between 0 and 6),  -- 0=Sun..6=Sat; NULL = unscheduled/rotating
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
  logged_on date not null, started_at timestamptz, ended_at timestamptz, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
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
  rpe numeric(3,1) check (rpe between 0 and 10),   -- optional rating scale, 0.5 increments
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
```
Weight = grams (`weight_g`), matching `health_logs.weight_g`; display via `gToKg()`. `rpe numeric(3,1)` is the one non-integer (bounded rating scale, 0.5 steps) — documented as a code comment. Variations are ordinary `exercises` rows with `parent_exercise_id` set (tracked as their own progress curve).

### C.2 Seed exercises (~15, shared)
Barbell Bench Press, Incline Barbell Bench Press, Dumbbell Bench Press (chest); Barbell Back Squat, Leg Press, Romanian Deadlift (legs); Barbell Deadlift, Pull-up, Barbell Row, Lat Pulldown (back); Overhead Press, Dumbbell Shoulder Press (shoulders); Dumbbell Bicep Curl (unilateral), Tricep Pushdown (arms); Plank (core). After insert, set `parent_exercise_id` of the two bench variations to Barbell Bench Press.

### C.3 Progress derivation (JS, `src/lib/gym/progress.ts`, never stored)
- **Est. 1RM (Epley):** `weight_g * (1 + reps/30)` per set; max over a window = "best est. 1RM."
- **PR:** `max(weight_g)` per exercise (optionally reps≥threshold).
- **Session volume (tonnage):** `sum(weight_g * reps)` per session.
- **Volume-over-time chart:** per exercise, sum `weight_g*reps` per session by `logged_on`, plot time series (reuse `WeightChart.svelte` approach).
- **Session streak:** reuse the existing streak util (`0007_streak.sql` / `src/lib/streak`) — distinct days with ≥1 session, break on gap >1 day.
- **Weekly muscle-group frequency:** join `session_sets`→`exercises.muscle_group`→`workout_sessions.logged_on`, count distinct `(logged_on, muscle_group)` in trailing 7 days.

### C.4 Coexistence with `fitness_logs`
Keep `fitness_logs` unchanged for free-form/cardio (runs, swims, yoga). New tables are additive, for structured lifting only (Epley on a run is meaningless; cardio has no reps/weight). Integration is UI-only: the Fitness "Today" screen queries both and merges into one activity feed sorted by `created_at`, with different card templates. No schema coupling.

### C.5 Gym UX (mobile-first)
- **Plan builder (`/fitness/plan`):** list plans → plan shows `plan_days` as weekday chips (+ "Unscheduled" section) → edit a day = reorderable `plan_exercises` (`Exercise · 3×8-12`), "+ Add exercise" uses the catalog search-chip pattern then a small target sets/reps/weight form. Reuse an existing reorderable-list pattern if one exists.
- **Today's workout (`/fitness/workouts`):** if today's weekday matches an active-plan `plan_day`, show "Start [Push Day]"; if a session exists for today, resume it. Start → create `workout_sessions` (plan_day_id, started_at) → exercise cards with fast set rows `Set 1: [reps][weight][✓]`; ✓ inserts a `session_sets` row and reveals next set pre-filled with prior weight; "+" adds an extra set. Large steppers/number-pad; weight in 2.5/1.25 kg increments, reps in 1s. Finish → set `ended_at`, show summary (volume, sets done vs planned, duration). **Freestyle:** session with `plan_day_id = null`, add exercises on the fly.
- **Progress (`/fitness/progress`):** exercise picker → est-1RM line chart; PR stats; weekly muscle-group frequency bar; session streak counter.

---

## Migrations & files, in build order

| File | Contents |
|---|---|
| `supabase/migrations/0012_invites.sql` | `invites` + RLS (A) |
| `supabase/functions/redeem-invite/index.ts` | Edge Function (A) — deployed separately, not in migration sequence |
| `src/routes/(auth)/signup/+page.svelte`, invite-management UI, profile auto-create | A |
| `supabase/migrations/0013_food_nutrition.sql` | `nutrients`, `food_items`, `food_nutrient_values`, `food_log_entries`, `nutrition_goals` + RLS + seed (26 nutrients, 30 foods, ~120 values) (B) |
| `src/lib/nutrition/*`, `src/routes/(app)/fitness/+layout.svelte` + `/food` route | B |
| `supabase/migrations/0014_gym.sql` | `exercises`, `workout_plans`, `plan_days`, `plan_exercises`, `workout_sessions`, `session_sets` + RLS + seed (~15 exercises) (C) |
| `src/lib/gym/*`, `/fitness/workouts`, `/fitness/plan`, `/fitness/progress` routes | C |
| `src/lib/nav.ts` | fan-menu additions (A/B/C) |
| `tests/unit/rls.test.ts` | isolation tests: profile/invites, private vs shared food_items/exercises |

## Risks

1. **First backend function.** No `supabase/functions/` exists yet. CORS, service-role env injection, and hosted deploy are new ground. Test redemption end-to-end against the **hosted** project; add an integration test hitting the deployed URL with a bad code → expect 4xx.
2. **Subquery RLS on `food_nutrient_values`/`session_sets`** is more complex than the flat pattern — a bug could leak shared-catalog writes or block reads. Needs its own explicit RLS test (A/B read-shared, cannot-read/write-private for both new junction-style tables).
3. **Seed nutrition accuracy is best-effort.** Label catalog facts "est." in the UI; don't present false precision.
4. **Offline sync of a shared read-only catalog is new.** `food_items`/`exercises` mix `user_id IS NULL` (pull-only) with owned (bidirectional) rows — the first such case. Review `src/lib/data/sync-queue.ts` before implementing so shared rows sync **down only** and aren't queued for upload or excluded from the offline cache.
5. **`quantity`/`rpe` `numeric` exception** to "integers everywhere." Preserve the justification as a code comment on both columns so it survives independent of this spec.

## What requires the owner (not code)
- Deploy the edge function to the **hosted** Supabase project (`supabase functions deploy redeem-invite`) and set `site_url`/redirect URLs — needs the owner's Supabase account/access. Everything else is implementable and locally testable end-to-end.
