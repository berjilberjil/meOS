import { z } from 'zod';
import {
  addSlotFood,
  catalog,
  clearSlot,
  clearWeek,
  deleteLogItem,
  emptyNutrition,
  foodById,
  logFood,
  logPlannedMeal,
  normalizeMeal,
  planItems,
  removeSlotFood,
  searchFoods,
  setSlot,
  totalsForItems,
  upsertCustomFood,
  weekdayFromDate,
  type Food,
  type Macros,
  type NutritionState,
  type PlanItem
} from '../../../diet/src/plan.ts';
import {
  STATE_KEYS,
  DEFAULT_FITNESS_PROFILE,
  DEFAULT_PROFILE,
  type FitnessDay,
  type FitnessProfile,
  type Profile
} from '../schemas/models.ts';
import { errors } from '../utils/errors.ts';
import { ok } from '../utils/result.ts';
import { assertDateKey, todayKey } from '../utils/dates.ts';
import { newId } from '../utils/ids.ts';
import type { ToolContext, ToolDefinition } from './registry.ts';
import { readObject } from './shared.ts';
import { calorieTargets as computeTargets, latestWeight } from '../services/nutrition.ts';

const MEALS = ['breakfast', 'lunch', 'dinner', 'snacks', 'snack'] as const;
const FOOD_CATEGORIES = ['protein', 'carb', 'veg', 'dairy', 'fruit', 'drink', 'junk', 'other'] as const;

function stateOrEmpty(n: NutritionState | null): NutritionState {
  const s = n ?? emptyNutrition();
  return { ...s, customFoods: s.customFoods ?? [], log: s.log ?? {}, mealPlan: s.mealPlan ?? {} };
}

async function mutateNutrition(
  ctx: ToolContext,
  transform: (current: NutritionState) => NutritionState
): Promise<NutritionState> {
  let result = emptyNutrition();
  await ctx.services.store.update<NutritionState>(STATE_KEYS.nutrition, (current) => {
    result = transform(stateOrEmpty(current));
    return result;
  });
  return result;
}

function mealKey(raw: string): string {
  try {
    return normalizeMeal(raw);
  } catch {
    throw errors.invalidInput(`meal must be one of: ${MEALS.join(', ')}`);
  }
}

function assertFood(id: string, custom: Food[]): string {
  const food = catalog(custom).find((f) => f.id === id);
  if (!food) throw errors.invalidInput(`No food with id "${id}". Use meos_diet_search_foods first.`);
  return food.id;
}

function quantity(value: number | undefined): number {
  const q = value ?? 1;
  if (!Number.isFinite(q) || q <= 0 || q > 100) throw errors.invalidInput('quantity must be between 0 and 100');
  return q;
}

function describeItem(item: PlanItem, custom: Food[], override?: Partial<PlanItem>) {
  const merged = { ...item, ...(override ?? {}) };
  const food = foodById(merged.foodId, custom);
  const macros = food ? food.perServing : null;
  const scale = (v: number) => Math.round(v * merged.quantity * 10) / 10;
  return {
    id: merged.id,
    food_id: merged.foodId,
    name: food?.name ?? 'unknown',
    serving: food?.servingLabel ?? null,
    quantity: merged.quantity,
    kcal: macros ? scale(macros.calories) : 0,
    protein_g: macros ? scale(macros.protein) : 0,
    carb_g: macros ? scale(macros.carbs) : 0,
    fat_g: macros ? scale(macros.fats) : 0,
    fiber_g: macros ? scale(macros.fiber) : 0
  };
}

function dayLogView(state: NutritionState, date: string) {
  const day = state.log[date] ?? { meals: {}, skipped: [], confirmed: [] };
  const meals: Record<string, unknown> = {};
  const all: PlanItem[] = [];
  for (const meal of ['breakfast', 'lunch', 'dinner', 'snacks']) {
    const items = day.meals?.[meal] ?? [];
    all.push(...items);
    meals[meal] = items.map((i) => describeItem(i, state.customFoods));
  }
  const totals = totalsForItems(all, state.customFoods);
  return {
    date,
    meals,
    totals: {
      energy_kcal: Math.round(totals.calories),
      protein_g: Math.round(totals.protein * 10) / 10,
      carb_g: Math.round(totals.carbs * 10) / 10,
      fat_g: Math.round(totals.fats * 10) / 10,
      fiber_g: Math.round(totals.fiber * 10) / 10
    },
    skipped: day.skipped ?? [],
    confirmed: day.confirmed ?? []
  };
}

function weekdayOrDate(args: any): string {
  if (args.date) return weekdayFromDate(assertDateKey(args.date));
  if (args.weekday != null) {
    const wd = Number(args.weekday);
    if (!Number.isInteger(wd) || wd < 0 || wd > 6) throw errors.invalidInput('weekday must be 0 (Sun) … 6 (Sat)');
    return String(wd);
  }
  return weekdayFromDate(todayKey());
}

export const dietTools: ToolDefinition[] = [
  {
    name: 'meos_diet_get_context',
    title: 'Get diet context',
    description:
      'The native MeOS diet context: profile, goals, today\'s planned meals and today\'s logged intake vs targets. Start here for any diet question. Uses the same nutrition model as the Diet tab.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const profile = await readObject<Profile>(ctx, STATE_KEYS.profile, DEFAULT_PROFILE);
      const fp = await readObject<FitnessProfile>(ctx, STATE_KEYS.fitnessProfile, DEFAULT_FITNESS_PROFILE);
      const fitness = await readObject<Record<string, FitnessDay>>(ctx, STATE_KEYS.fitness, {});
      const today = todayKey();
      const wd = weekdayFromDate(today);
      const planned = ['breakfast', 'lunch', 'dinner', 'snacks'].flatMap((m) => planItems(nutrition, wd, m));
      const logged = dayLogView(nutrition, today);
      return ok({
        date: today,
        weekday: Number(wd),
        profile: { height_cm: profile.heightCm ?? null, age: profile.age ?? null, sex: fp.sex, goal: fp.goal },
        goals: {
          stored: { energy_kcal: fp.calorieTargetKcal ?? null, protein_g: fp.proteinTargetG ?? null },
          computed: (() => {
            const t = computeTargets(profile, fp, latestWeight(fitness)?.kg ?? null);
            return t
              ? {
                  energy_kcal: t.goal_calories,
                  protein_g: t.protein_g,
                  carb_g: t.carb_g,
                  fat_g: t.fat_g,
                  bmr: t.bmr,
                  tdee: t.tdee
                }
              : null;
          })()
        },
        today_plan: {
          totals: (() => {
            const t = totalsForItems(planned, nutrition.customFoods);
            return {
              energy_kcal: Math.round(t.calories),
              protein_g: Math.round(t.protein * 10) / 10,
              carb_g: Math.round(t.carbs * 10) / 10,
              fat_g: Math.round(t.fats * 10) / 10
            };
          })(),
          items: planned.map((i) => describeItem(i, nutrition.customFoods))
        },
        today_log: logged
      });
    }
  },

  {
    name: 'meos_diet_get_week_plan',
    title: 'Get weekly meal plan',
    description: 'Read the Sun–Sat meal plan (weekday 0 = Sunday) with per-meal items, names and macro totals.',
    inputSchema: {},
    scopes: ['read', 'health'],
    async handler(_args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const days = ['0', '1', '2', '3', '4', '5', '6'].map((wd) => {
        const meals: Record<string, unknown> = {};
        const all: PlanItem[] = [];
        for (const meal of ['breakfast', 'lunch', 'dinner', 'snacks']) {
          const items = planItems(nutrition, wd, meal);
          all.push(...items);
          meals[meal] = items.map((i) => describeItem(i, nutrition.customFoods));
        }
        const t = totalsForItems(all, nutrition.customFoods);
        return {
          weekday: Number(wd),
          totals: {
            energy_kcal: Math.round(t.calories),
            protein_g: Math.round(t.protein * 10) / 10,
            carb_g: Math.round(t.carbs * 10) / 10,
            fat_g: Math.round(t.fats * 10) / 10
          },
          meals
        };
      });
      return ok({ weekdays: '0=Sun … 6=Sat', days });
    }
  },

  {
    name: 'meos_diet_get_day_log',
    title: 'Get a day\'s meals',
    description: 'Read what was actually eaten on one date, with per-item macros and totals. This is the log, not the plan.',
    inputSchema: { date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/) },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      return ok(dayLogView(nutrition, assertDateKey(args.date)));
    }
  },

  {
    name: 'meos_diet_search_foods',
    title: 'Search foods',
    description: 'Search the native food library (seed foods plus custom foods). Use the returned id with the logging tools.',
    inputSchema: {
      query: z.string().max(120).optional(),
      limit: z.number().int().min(1).max(40).optional()
    },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const rows = searchFoods(String(args.query ?? ''), Math.min(args.limit ?? 12, 40), nutrition.customFoods).map((f) => ({
        id: f.id,
        name: f.name,
        category: f.category,
        serving: f.servingLabel,
        kcal: f.perServing.calories,
        protein_g: f.perServing.protein,
        carb_g: f.perServing.carbs,
        fat_g: f.perServing.fats,
        fiber_g: f.perServing.fiber
      }));
      return ok({ foods: rows, returned: rows.length });
    }
  },

  {
    name: 'meos_diet_list_recent_foods',
    title: 'List recent foods',
    description: 'Foods most recently used in the meal log, newest first.',
    inputSchema: { limit: z.number().int().min(1).max(30).optional() },
    scopes: ['read', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const seen: string[] = [];
      for (const date of Object.keys(nutrition.log).sort().reverse()) {
        for (const items of Object.values(nutrition.log[date]?.meals ?? {})) {
          for (const item of items) {
            if (!seen.includes(item.foodId)) seen.push(item.foodId);
            if (seen.length >= (args.limit ?? 10)) break;
          }
        }
        if (seen.length >= (args.limit ?? 10)) break;
      }
      return ok({
        foods: seen
          .map((id) => foodById(id, nutrition.customFoods))
          .filter((f): f is Food => Boolean(f))
          .map((f) => ({ id: f.id, name: f.name, category: f.category, serving: f.servingLabel, kcal: f.perServing.calories }))
      });
    }
  },

  {
    name: 'meos_diet_set_meal_slot',
    title: 'Set a planned meal',
    description:
      'Replace one meal slot in the weekly plan. Pass weekday (0=Sun…6=Sat) or a date. Every food id must exist in the library.',
    inputSchema: {
      weekday: z.number().int().min(0).max(6).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      meal: z.enum(MEALS),
      foods: z
        .array(z.object({ food_id: z.string().min(1), quantity: z.number().positive().max(100) }))
        .max(50)
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const wd = weekdayOrDate(args);
      const meal = mealKey(args.meal);
      const foods = args.foods.map((f: any) => ({
        foodId: assertFood(f.food_id, nutrition.customFoods),
        quantity: quantity(f.quantity)
      }));
      const next = await mutateNutrition(ctx, (current) => setSlot(current, wd, meal, foods));
      return ok({ weekday: Number(wd), meal, items: planItems(next, wd, meal).map((i) => describeItem(i, next.customFoods)) }, {
        written: STATE_KEYS.nutrition
      });
    }
  },

  {
    name: 'meos_diet_add_food_to_slot',
    title: 'Add a food to a planned meal',
    description: 'Append one food to a planned meal slot without replacing the rest of the slot.',
    inputSchema: {
      weekday: z.number().int().min(0).max(6).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      meal: z.enum(MEALS),
      food_id: z.string().min(1),
      quantity: z.number().positive().max(100).optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const wd = weekdayOrDate(args);
      const meal = mealKey(args.meal);
      const foodId = assertFood(args.food_id, nutrition.customFoods);
      const next = await mutateNutrition(ctx, (current) =>
        addSlotFood(current, wd, meal, foodId, quantity(args.quantity))
      );
      return ok({ weekday: Number(wd), meal, items: planItems(next, wd, meal).map((i) => describeItem(i, next.customFoods)) }, {
        written: STATE_KEYS.nutrition
      });
    }
  },

  {
    name: 'meos_diet_remove_slot_food',
    title: 'Remove a planned food',
    description: 'Remove one planned row by its item id (returned by the plan tools).',
    inputSchema: { item_id: z.string().min(1) },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      await mutateNutrition(ctx, (current) => removeSlotFood(current, args.item_id));
      return ok({ removed: true, item_id: args.item_id }, { written: STATE_KEYS.nutrition });
    }
  },

  {
    name: 'meos_diet_clear_meal_slot',
    title: 'Clear a planned meal',
    description: 'Clear one meal slot in the weekly plan. Other meals are untouched.',
    inputSchema: {
      weekday: z.number().int().min(0).max(6).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
      meal: z.enum(MEALS)
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const wd = weekdayOrDate(args);
      await mutateNutrition(ctx, (current) => clearSlot(current, wd, mealKey(args.meal)));
      return ok({ cleared: true, weekday: Number(wd), meal: args.meal }, { written: STATE_KEYS.nutrition });
    }
  },

  {
    name: 'meos_diet_clear_week_plan',
    title: 'Clear the weekly meal plan',
    description:
      'Empty the entire weekly meal plan. It does not touch anyone\'s meal log. Requires destructive scope and confirm=true because the plan cannot be recovered from the recycle bin.',
    inputSchema: { confirm: z.boolean().optional() },
    scopes: ['write', 'health', 'destructive'],
    destructive: true,
    async handler(_args, ctx) {
      await mutateNutrition(ctx, (current) => clearWeek(current));
      return ok({ cleared: true }, { written: STATE_KEYS.nutrition, note: 'Meal logs were preserved.' });
    }
  },

  {
    name: 'meos_diet_log_food',
    title: 'Log a food eaten',
    description: 'Log a food actually eaten on a date (default today). This writes to the meal log, not the plan.',
    inputSchema: {
      food_id: z.string().min(1),
      meal: z.enum(MEALS),
      quantity: z.number().positive().max(100).optional(),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const date = assertDateKey(args.date ?? todayKey());
      const foodId = assertFood(args.food_id, nutrition.customFoods);
      const next = await mutateNutrition(ctx, (current) =>
        logFood(current, date, mealKey(args.meal), foodId, quantity(args.quantity))
      );
      return ok(dayLogView(next, date), { written: STATE_KEYS.nutrition });
    }
  },

  {
    name: 'meos_diet_log_planned_meal',
    title: 'Log a planned meal',
    description:
      'Copy the planned meal for a date into that day\'s log. Refuses when nothing is planned, or when the meal is already logged, rather than overwriting what was eaten.',
    inputSchema: {
      meal: z.enum(MEALS),
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const date = assertDateKey(args.date ?? todayKey());
      const meal = mealKey(args.meal);
      const wd = weekdayFromDate(date);
      if (planItems(nutrition, wd, meal).length === 0) {
        throw errors.conflict(`Nothing planned for ${meal} on ${date}.`);
      }
      const day = nutrition.log[date];
      if ((day?.meals?.[meal] ?? []).length > 0 || (day?.confirmed ?? []).includes(meal)) {
        throw errors.conflict(`${meal} on ${date} is already logged.`);
      }
      const next = await mutateNutrition(ctx, (current) => logPlannedMeal(current, date, wd, meal));
      return ok(dayLogView(next, date), { written: STATE_KEYS.nutrition });
    }
  },

  {
    name: 'meos_diet_delete_log_item',
    title: 'Delete a logged food',
    description:
      'Remove one logged meal row by id. Meal-log rows are not kept in the recycle bin, so this needs destructive scope and confirm=true.',
    inputSchema: { log_id: z.string().min(1), confirm: z.boolean().optional() },
    scopes: ['write', 'health', 'destructive'],
    destructive: true,
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const exists = Object.values(nutrition.log).some((day) =>
        Object.values(day.meals ?? {}).some((items) => items.some((i) => i.id === args.log_id))
      );
      if (!exists) throw errors.notFound('Meal log row');
      await mutateNutrition(ctx, (current) => deleteLogItem(current, args.log_id));
      return ok({ deleted: true, log_id: args.log_id }, { written: STATE_KEYS.nutrition });
    }
  },

  {
    name: 'meos_diet_upsert_food',
    title: 'Create or update a food',
    description:
      'Add a custom food, or update only the supplied fields of an existing food matched by id or name. Macros are per one serving. Other macros are preserved on update.',
    inputSchema: {
      id: z.string().max(120).optional(),
      name: z.string().min(1).max(120),
      category: z.enum(FOOD_CATEGORIES).optional(),
      serving_label: z.string().max(80).optional(),
      energy_kcal: z.number().min(0).max(10000).optional(),
      protein_g: z.number().min(0).max(1000).optional(),
      carb_g: z.number().min(0).max(1000).optional(),
      fat_g: z.number().min(0).max(1000).optional(),
      fiber_g: z.number().min(0).max(1000).optional(),
      vitamins: z.string().max(200).optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      const nutrition = stateOrEmpty(await readObject<NutritionState>(ctx, STATE_KEYS.nutrition, emptyNutrition()));
      const name = args.name.trim();
      if (!name) throw errors.invalidInput('name is required');
      const all = catalog(nutrition.customFoods);
      const existing =
        (args.id ? all.find((f) => f.id === args.id) : undefined) ??
        all.find((f) => f.name.trim().toLowerCase() === name.toLowerCase());

      const macros: Macros = {
        calories: args.energy_kcal ?? existing?.perServing.calories ?? 0,
        protein: args.protein_g ?? existing?.perServing.protein ?? 0,
        carbs: args.carb_g ?? existing?.perServing.carbs ?? 0,
        fats: args.fat_g ?? existing?.perServing.fats ?? 0,
        fiber: args.fiber_g ?? existing?.perServing.fiber ?? 0
      };
      const food: Food = {
        id: existing?.id ?? args.id ?? newId(),
        name,
        category: args.category ?? existing?.category ?? 'other',
        servingLabel: args.serving_label ?? existing?.servingLabel ?? '1 serving',
        perServing: macros,
        vitamins: args.vitamins ?? existing?.vitamins,
        isDefault: false
      };
      await mutateNutrition(ctx, (current) => upsertCustomFood(current, food));
      return ok({ id: food.id, name: food.name, serving: food.servingLabel, per_serving: food.perServing }, {
        written: STATE_KEYS.nutrition
      });
    }
  },

  {
    name: 'meos_diet_set_goals',
    title: 'Set diet goals',
    description: 'Update the calorie and/or protein target stored on the fitness profile. Other fitness settings are preserved.',
    inputSchema: {
      energy_kcal: z.number().min(500).max(20000).nullable().optional(),
      protein_g: z.number().min(0).max(1000).nullable().optional()
    },
    scopes: ['write', 'health'],
    async handler(args, ctx) {
      if (args.energy_kcal === undefined && args.protein_g === undefined) {
        throw errors.invalidInput('Nothing to update');
      }
      let saved: FitnessProfile = DEFAULT_FITNESS_PROFILE;
      await ctx.services.store.update<FitnessProfile>(STATE_KEYS.fitnessProfile, (current) => {
        saved = { ...(current ?? DEFAULT_FITNESS_PROFILE) };
        if (args.energy_kcal !== undefined) saved.calorieTargetKcal = args.energy_kcal;
        if (args.protein_g !== undefined) saved.proteinTargetG = args.protein_g;
        return saved;
      });
      return ok({ fitness_profile: saved }, { written: STATE_KEYS.fitnessProfile });
    }
  }
];
