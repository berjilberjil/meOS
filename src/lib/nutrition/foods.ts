import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import type { FoodItem, FoodLogEntry, FoodNutrientValue, Meal, Nutrient, NutritionGoals } from './types';

// The 0013 tables aren't in the generated Database types; reach them via an
// untyped client (as SupabaseRepository does internally for dynamic tables).
function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export const foodItemsRepo = new SupabaseRepository<FoodItem>('food_items');
export const foodLogRepo = new SupabaseRepository<FoodLogEntry>('food_log_entries');

export async function listNutrients(): Promise<Nutrient[]> {
	const { data } = await db().from('nutrients').select('*').order('sort_order');
	return (data ?? []) as Nutrient[];
}

// Shared (user_id null) + own custom foods, per RLS.
export function listFoods(): Promise<FoodItem[]> {
	return foodItemsRepo.list();
}

export async function listNutrientValues(): Promise<FoodNutrientValue[]> {
	const { data } = await db().from('food_nutrient_values').select('*');
	return (data ?? []) as FoodNutrientValue[];
}

export async function listLogFor(dateIso: string): Promise<FoodLogEntry[]> {
	const { data } = await db().from('food_log_entries').select('*').eq('logged_on', dateIso);
	return (data ?? []) as FoodLogEntry[];
}

// Last N distinct foods this user logged (for one-tap re-log), most recent first.
export async function recentFoodIds(limit = 10): Promise<string[]> {
	const { data } = await db()
		.from('food_log_entries')
		.select('food_id, created_at')
		.order('created_at', { ascending: false })
		.limit(60);
	const seen: string[] = [];
	for (const r of (data ?? []) as { food_id: string }[]) {
		if (!seen.includes(r.food_id)) seen.push(r.food_id);
		if (seen.length >= limit) break;
	}
	return seen;
}

export function logFood(input: {
	food_id: string;
	quantity: number;
	logged_on: string;
	meal?: Meal | null;
}): Promise<FoodLogEntry> {
	return foodLogRepo.create({
		food_id: input.food_id,
		quantity: input.quantity,
		logged_on: input.logged_on,
		meal: input.meal ?? null
	} as Partial<FoodLogEntry>);
}

export function deleteLog(id: string): Promise<void> {
	return foodLogRepo.remove(id);
}

// Create a private custom food + its macro values (protein/carb/fat/fiber in mg).
export async function createCustomFood(
	food: {
		name: string;
		category: string;
		default_serving_label: string;
		serving_grams: number;
		energy_kcal: number;
	},
	macros: { protein_mg: number; carb_mg: number; fat_mg: number; fiber_mg: number },
	nutrients: Nutrient[]
): Promise<FoodItem> {
	const created = await foodItemsRepo.create(food as Partial<FoodItem>);
	const idByKey = new Map(nutrients.map((n) => [n.key, n.id]));
	const rows = (
		[
			['protein', macros.protein_mg],
			['carb', macros.carb_mg],
			['fat', macros.fat_mg],
			['fiber', macros.fiber_mg]
		] as const
	)
		.map(([k, amount]) => ({ food_id: created.id, nutrient_id: idByKey.get(k), amount }))
		.filter((r) => r.nutrient_id && r.amount > 0);
	if (rows.length) {
		const { error } = await db().from('food_nutrient_values').insert(rows);
		if (error) throw error;
	}
	return created;
}

const EMPTY_GOALS: NutritionGoals = {
	energy_kcal: null,
	protein_mg: null,
	carb_mg: null,
	fat_mg: null,
	fiber_mg: null
};

export async function getNutritionGoals(): Promise<NutritionGoals> {
	const { data } = await db()
		.from('nutrition_goals')
		.select('energy_kcal, protein_mg, carb_mg, fat_mg, fiber_mg')
		.maybeSingle();
	return (data as NutritionGoals | null) ?? EMPTY_GOALS;
}

export async function saveNutritionGoals(g: NutritionGoals): Promise<void> {
	const client = db();
	const { data } = await client.from('nutrition_goals').select('user_id').maybeSingle();
	if (data) {
		const { error } = await client
			.from('nutrition_goals')
			.update(g)
			.eq('user_id', (data as { user_id: string }).user_id);
		if (error) throw error;
	} else {
		const { error } = await client.from('nutrition_goals').insert(g);
		if (error) throw error;
	}
}
