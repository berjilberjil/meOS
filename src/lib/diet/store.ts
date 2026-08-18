import type { SupabaseClient } from '@supabase/supabase-js';
import { todayIso } from '../finance/dates';
import {
	dailyTotals,
	entryTotals,
	groupValuesByFood,
	nutrientKeyById,
	type FoodTotals
} from '../nutrition/calc';
import type {
	FoodItem,
	FoodLogEntry,
	FoodNutrientValue,
	Meal,
	Nutrient,
	NutritionGoals
} from '../nutrition/types';
import type { Personal } from '../profile/personal';
import type { HealthLog } from '../health/types';
import { plannedMealToLogEntries, planDayTotals, slotsForMeal } from './plan';
import type { DietSlot, DietWeek, SlotFoodInput } from './types';
import { dateForWeekday, weekStartMonday, weekdayIndex } from './week';

const EMPTY_GOALS: NutritionGoals = {
	energy_kcal: null,
	protein_mg: null,
	carb_mg: null,
	fat_mg: null,
	fiber_mg: null
};

const EMPTY_PERSONAL: Personal = {
	current_weight_kg: null,
	goal_weight_kg: null,
	height_cm: null,
	blood_group: null,
	dob: null,
	sex: null
};

function asDb(client: SupabaseClient): SupabaseClient {
	return client as unknown as SupabaseClient;
}

function coerceSlot(row: DietSlot): DietSlot {
	return {
		...row,
		quantity: Number(row.quantity),
		weekday: Number(row.weekday),
		sort_order: Number(row.sort_order)
	};
}

export interface FoodHit {
	id: string;
	name: string;
	category: string;
	default_serving_label: string;
	serving_grams: number;
	energy_kcal: number;
	protein_mg: number;
}

export interface WeekPlanView {
	week: DietWeek;
	week_start: string;
	slots: DietSlot[];
	days: Array<{
		weekday: number;
		date: string;
		totals: FoodTotals;
	}>;
}

export function createDietStore(client: SupabaseClient) {
	const db = asDb(client);

	async function requireUserId(): Promise<string> {
		const { data, error } = await client.auth.getUser();
		if (error) throw error;
		const uid = data.user?.id;
		if (!uid) throw new Error('Not signed in');
		return uid;
	}

	async function listNutrients(): Promise<Nutrient[]> {
		const { data, error } = await db.from('nutrients').select('*').order('sort_order');
		if (error) throw error;
		return (data ?? []) as Nutrient[];
	}

	async function listFoods(): Promise<FoodItem[]> {
		const { data, error } = await db.from('food_items').select('*').order('name');
		if (error) throw error;
		return (data ?? []) as FoodItem[];
	}

	async function listNutrientValues(): Promise<FoodNutrientValue[]> {
		const { data, error } = await db.from('food_nutrient_values').select('*');
		if (error) throw error;
		return (data ?? []) as FoodNutrientValue[];
	}

	async function listLogFor(dateIso: string): Promise<FoodLogEntry[]> {
		const { data, error } = await db.from('food_log_entries').select('*').eq('logged_on', dateIso);
		if (error) throw error;
		return (data ?? []) as FoodLogEntry[];
	}

	async function getNutritionGoals(): Promise<NutritionGoals> {
		const { data, error } = await db
			.from('nutrition_goals')
			.select('energy_kcal, protein_mg, carb_mg, fat_mg, fiber_mg')
			.maybeSingle();
		if (error) throw error;
		return (data as NutritionGoals | null) ?? EMPTY_GOALS;
	}

	async function getPersonal(): Promise<Personal> {
		const { data, error } = await db.from('profile').select('preferences').maybeSingle();
		if (error) throw error;
		const prefs = (data?.preferences ?? {}) as Partial<Personal>;
		return { ...EMPTY_PERSONAL, ...prefs };
	}

	async function latestWeight(): Promise<{ logged_on: string; weight_g: number } | null> {
		const { data, error } = await db
			.from('health_logs')
			.select('logged_on, weight_g')
			.not('weight_g', 'is', null)
			.order('logged_on', { ascending: false })
			.limit(1)
			.maybeSingle();
		if (error) throw error;
		const row = data as Pick<HealthLog, 'logged_on' | 'weight_g'> | null;
		if (!row || row.weight_g == null) return null;
		return { logged_on: row.logged_on, weight_g: row.weight_g };
	}

	async function catalogMaps() {
		const [foods, values, nutrients] = await Promise.all([
			listFoods(),
			listNutrientValues(),
			listNutrients()
		]);
		return {
			foods,
			foodById: new Map(foods.map((f) => [f.id, f])),
			valuesByFood: groupValuesByFood(values),
			keyById: nutrientKeyById(nutrients),
			nutrients
		};
	}

	function proteinOf(
		food: FoodItem,
		valuesByFood: Map<string, FoodNutrientValue[]>,
		keyById: Map<string, string>
	): number {
		return entryTotals(1, food, valuesByFood.get(food.id) ?? [], keyById).protein_mg;
	}

	async function ensureWeek(dateOrMonday: string): Promise<DietWeek> {
		const week_start = weekStartMonday(dateOrMonday);
		const { data: existing, error: readErr } = await db
			.from('diet_weeks')
			.select('*')
			.eq('week_start', week_start)
			.maybeSingle();
		if (readErr) throw readErr;
		if (existing) return existing as DietWeek;

		const { data, error } = await db.from('diet_weeks').insert({ week_start }).select().single();
		if (!error && data) return data as DietWeek;

		const { data: raced, error: racedErr } = await db
			.from('diet_weeks')
			.select('*')
			.eq('week_start', week_start)
			.maybeSingle();
		if (raced) return raced as DietWeek;
		throw error ?? racedErr ?? new Error('could not create diet week');
	}

	async function listSlots(weekId: string): Promise<DietSlot[]> {
		const { data, error } = await db
			.from('diet_slots')
			.select('*')
			.eq('week_id', weekId)
			.order('weekday')
			.order('meal')
			.order('sort_order');
		if (error) throw error;
		return ((data ?? []) as DietSlot[]).map(coerceSlot);
	}

	async function getWeekPlan(dateOrMonday?: string): Promise<WeekPlanView> {
		const week = await ensureWeek(dateOrMonday ?? todayIso());
		const slots = await listSlots(week.id);
		const { foodById, valuesByFood, keyById } = await catalogMaps();
		const days = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({
			weekday,
			date: dateForWeekday(week.week_start, weekday),
			totals: planDayTotals(slots, weekday, foodById, valuesByFood, keyById)
		}));
		return { week, week_start: week.week_start, slots, days };
	}

	async function resolveWeek(input: { week_start?: string; date?: string }): Promise<DietWeek> {
		return ensureWeek(input.week_start ?? input.date ?? todayIso());
	}

	async function setSlot(
		input: { week_start?: string; date?: string; weekday: number; meal: Meal; foods: SlotFoodInput[] }
	): Promise<DietSlot[]> {
		const week = await resolveWeek(input);
		const { data, error } = await db.rpc('replace_diet_slot', {
			p_week_id: week.id,
			p_weekday: input.weekday,
			p_meal: input.meal,
			p_foods: input.foods
		});
		if (error) throw error;
		return ((data ?? []) as DietSlot[]).map(coerceSlot);
	}

	async function addSlotFood(input: {
		week_start?: string;
		date?: string;
		weekday: number;
		meal: Meal;
		food_id: string;
		quantity: number;
	}): Promise<DietSlot> {
		const week = await resolveWeek(input);
		const existing = slotsForMeal(await listSlots(week.id), input.weekday, input.meal);
		const sort_order = existing.reduce((m, s) => Math.max(m, s.sort_order + 1), 0);
		const { data, error } = await db
			.from('diet_slots')
			.insert({
				week_id: week.id,
				weekday: input.weekday,
				meal: input.meal,
				food_id: input.food_id,
				quantity: input.quantity,
				sort_order
			})
			.select()
			.single();
		if (error) throw error;
		return coerceSlot(data as DietSlot);
	}

	async function removeSlotFood(id: string): Promise<void> {
		const { error, count } = await db
			.from('diet_slots')
			.delete({ count: 'exact' })
			.eq('id', id);
		if (error) throw error;
		if (!count) throw new Error('slot not found');
	}

	async function clearSlot(input: {
		week_start?: string;
		date?: string;
		weekday: number;
		meal: Meal;
	}): Promise<void> {
		await setSlot({ ...input, foods: [] });
	}

	async function searchFoods(query: string, limit = 12): Promise<FoodHit[]> {
		const q = query.trim().toLowerCase();
		const { foods, valuesByFood, keyById } = await catalogMaps();
		const hits = (q ? foods.filter((f) => f.name.toLowerCase().includes(q)) : foods).slice(0, limit);
		return hits.map((f) => ({
			id: f.id,
			name: f.name,
			category: f.category,
			default_serving_label: f.default_serving_label,
			serving_grams: f.serving_grams,
			energy_kcal: f.energy_kcal,
			protein_mg: proteinOf(f, valuesByFood, keyById)
		}));
	}

	async function listRecentFoods(limit = 10): Promise<FoodHit[]> {
		const { data, error } = await db
			.from('food_log_entries')
			.select('food_id, created_at')
			.order('created_at', { ascending: false })
			.limit(60);
		if (error) throw error;
		const seen: string[] = [];
		for (const r of (data ?? []) as { food_id: string }[]) {
			if (!seen.includes(r.food_id)) seen.push(r.food_id);
			if (seen.length >= limit) break;
		}
		if (!seen.length) return [];
		const { foodById, valuesByFood, keyById } = await catalogMaps();
		return seen
			.map((id) => foodById.get(id))
			.filter((f): f is FoodItem => !!f)
			.map((f) => ({
				id: f.id,
				name: f.name,
				category: f.category,
				default_serving_label: f.default_serving_label,
				serving_grams: f.serving_grams,
				energy_kcal: f.energy_kcal,
				protein_mg: proteinOf(f, valuesByFood, keyById)
			}));
	}

	async function setGoals(input: {
		energy_kcal?: number | null;
		protein_g?: number | null;
		carb_g?: number | null;
		fat_g?: number | null;
		fiber_g?: number | null;
		protein_mg?: number | null;
		carb_mg?: number | null;
		fat_mg?: number | null;
		fiber_mg?: number | null;
	}): Promise<NutritionGoals> {
		const current = await getNutritionGoals();
		const g: NutritionGoals = {
			energy_kcal: input.energy_kcal === undefined ? current.energy_kcal : input.energy_kcal,
			protein_mg:
				input.protein_mg !== undefined
					? input.protein_mg
					: input.protein_g !== undefined
						? input.protein_g == null
							? null
							: Math.round(input.protein_g * 1000)
						: current.protein_mg,
			carb_mg:
				input.carb_mg !== undefined
					? input.carb_mg
					: input.carb_g !== undefined
						? input.carb_g == null
							? null
							: Math.round(input.carb_g * 1000)
						: current.carb_mg,
			fat_mg:
				input.fat_mg !== undefined
					? input.fat_mg
					: input.fat_g !== undefined
						? input.fat_g == null
							? null
							: Math.round(input.fat_g * 1000)
						: current.fat_mg,
			fiber_mg:
				input.fiber_mg !== undefined
					? input.fiber_mg
					: input.fiber_g !== undefined
						? input.fiber_g == null
							? null
							: Math.round(input.fiber_g * 1000)
						: current.fiber_mg
		};
		const { data: row } = await db.from('nutrition_goals').select('user_id').maybeSingle();
		if (row) {
			const { error } = await db
				.from('nutrition_goals')
				.update(g)
				.eq('user_id', (row as { user_id: string }).user_id);
			if (error) throw error;
		} else {
			const { error } = await db.from('nutrition_goals').insert(g);
			if (error) throw error;
		}
		return g;
	}

	async function upsertFood(input: {
		name: string;
		category?: string;
		serving_label?: string;
		serving_grams?: number;
		energy_kcal: number;
		protein_g?: number;
		carb_g?: number;
		fat_g?: number;
		fiber_g?: number;
	}): Promise<FoodItem> {
		const name = input.name.trim();
		if (!name) throw new Error('name is required');
		const user_id = await requireUserId();
		const { data: created, error } = await db
			.from('food_items')
			.insert({
				user_id,
				name,
				category: input.category ?? 'other',
				default_serving_label: input.serving_label ?? '1 serving',
				serving_grams: input.serving_grams ?? 100,
				energy_kcal: Math.round(input.energy_kcal)
			})
			.select()
			.single();
		if (error) throw error;
		const food = created as FoodItem;
		const nutrients = await listNutrients();
		const idByKey = new Map(nutrients.map((n) => [n.key, n.id]));
		const rows = (
			[
				['protein', input.protein_g],
				['carb', input.carb_g],
				['fat', input.fat_g],
				['fiber', input.fiber_g]
			] as const
		)
			.map(([k, g]) => ({
				food_id: food.id,
				nutrient_id: idByKey.get(k),
				amount: g && g > 0 ? Math.round(g * 1000) : 0
			}))
			.filter((r) => r.nutrient_id && r.amount > 0);
		if (rows.length) {
			const { error: vErr } = await db.from('food_nutrient_values').insert(rows);
			if (vErr) throw vErr;
		}
		return food;
	}

	async function logFood(input: {
		food_id: string;
		quantity: number;
		logged_on?: string;
		meal: Meal;
	}): Promise<FoodLogEntry> {
		const { data, error } = await db
			.from('food_log_entries')
			.insert({
				food_id: input.food_id,
				quantity: input.quantity,
				logged_on: input.logged_on ?? todayIso(),
				meal: input.meal
			})
			.select()
			.single();
		if (error) throw error;
		return data as FoodLogEntry;
	}

	async function logPlannedMeal(input: {
		week_start?: string;
		date?: string;
		weekday?: number;
		meal: Meal;
	}): Promise<FoodLogEntry[]> {
		const loggedOn = input.date ?? todayIso();
		const weekday = input.weekday ?? weekdayIndex(loggedOn);
		const week = await resolveWeek({ week_start: input.week_start, date: loggedOn });
		const payloads = plannedMealToLogEntries(await listSlots(week.id), weekday, input.meal, loggedOn);
		if (!payloads.length) return [];
		const { data, error } = await db.from('food_log_entries').insert(payloads).select();
		if (error) throw error;
		return (data ?? []) as FoodLogEntry[];
	}

	async function deleteLog(id: string): Promise<void> {
		const { error, count } = await db
			.from('food_log_entries')
			.delete({ count: 'exact' })
			.eq('id', id);
		if (error) throw error;
		if (!count) throw new Error('log not found');
	}

	async function getDayLog(dateIso?: string) {
		const date = dateIso ?? todayIso();
		const [entries, goals, maps] = await Promise.all([
			listLogFor(date),
			getNutritionGoals(),
			catalogMaps()
		]);
		const totals = dailyTotals(entries, maps.foodById, maps.valuesByFood, maps.keyById);
		return {
			date,
			goals,
			totals,
			remaining: {
				energy_kcal: goals.energy_kcal == null ? null : goals.energy_kcal - totals.energy_kcal,
				protein_mg: goals.protein_mg == null ? null : goals.protein_mg - totals.protein_mg
			},
			entries: entries.map((e) => {
				const food = maps.foodById.get(e.food_id);
				const t = food
					? entryTotals(Number(e.quantity), food, maps.valuesByFood.get(e.food_id) ?? [], maps.keyById)
					: null;
				return {
					...e,
					quantity: Number(e.quantity),
					name: food?.name ?? 'unknown',
					energy_kcal: t?.energy_kcal ?? 0,
					protein_mg: t?.protein_mg ?? 0
				};
			})
		};
	}

	async function getContext() {
		const date = todayIso();
		const [personal, goals, weight, day, week] = await Promise.all([
			getPersonal(),
			getNutritionGoals(),
			latestWeight(),
			getDayLog(date),
			getWeekPlan(date)
		]);
		const todayWeekday = weekdayIndex(date);
		return {
			date,
			personal,
			goals,
			latest_weight: weight,
			today: day,
			today_plan: {
				weekday: todayWeekday,
				totals: week.days[todayWeekday]?.totals ?? null,
				slots: week.slots.filter((s) => s.weekday === todayWeekday)
			}
		};
	}

	return {
		listNutrients,
		listFoods,
		listNutrientValues,
		listLogFor,
		getNutritionGoals,
		getPersonal,
		ensureWeek,
		listSlots,
		getWeekPlan,
		setSlot,
		addSlotFood,
		removeSlotFood,
		clearSlot,
		searchFoods,
		listRecentFoods,
		setGoals,
		upsertFood,
		logFood,
		logPlannedMeal,
		deleteLog,
		getDayLog,
		getContext
	};
}

export type DietStore = ReturnType<typeof createDietStore>;
