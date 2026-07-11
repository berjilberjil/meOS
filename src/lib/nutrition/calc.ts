// Pure nutrition math — compute daily totals from log entries + the catalog.
// Never stored; computed at render time (mirrors finance/assets calc modules).
import type { FoodItem, FoodLogEntry, FoodNutrientValue, Nutrient } from './types';

export interface FoodTotals {
	energy_kcal: number;
	protein_mg: number;
	carb_mg: number;
	fat_mg: number;
	fiber_mg: number;
	micros: Record<string, number>; // nutrient key -> amount (in that nutrient's unit)
}

export function emptyTotals(): FoodTotals {
	return { energy_kcal: 0, protein_mg: 0, carb_mg: 0, fat_mg: 0, fiber_mg: 0, micros: {} };
}

export function nutrientKeyById(nutrients: Nutrient[]): Map<string, string> {
	return new Map(nutrients.map((n) => [n.id, n.key]));
}

export function groupValuesByFood(values: FoodNutrientValue[]): Map<string, FoodNutrientValue[]> {
	const m = new Map<string, FoodNutrientValue[]>();
	for (const v of values) {
		const arr = m.get(v.food_id) ?? [];
		arr.push(v);
		m.set(v.food_id, arr);
	}
	return m;
}

/** Totals for one logged item = per-serving amounts × quantity (rounded). */
export function entryTotals(
	quantity: number,
	food: Pick<FoodItem, 'energy_kcal'>,
	values: FoodNutrientValue[],
	keyById: Map<string, string>
): FoodTotals {
	const f = Number(quantity) || 0;
	const t = emptyTotals();
	t.energy_kcal = Math.round(food.energy_kcal * f);
	for (const v of values) {
		const key = keyById.get(v.nutrient_id);
		if (!key) continue;
		const amt = Math.round(v.amount * f);
		if (key === 'protein') t.protein_mg = amt;
		else if (key === 'carb') t.carb_mg = amt;
		else if (key === 'fat') t.fat_mg = amt;
		else if (key === 'fiber') t.fiber_mg = amt;
		else t.micros[key] = amt;
	}
	return t;
}

/** Sum totals across every entry for a day. */
export function dailyTotals(
	entries: FoodLogEntry[],
	foodById: Map<string, FoodItem>,
	valuesByFood: Map<string, FoodNutrientValue[]>,
	keyById: Map<string, string>
): FoodTotals {
	const total = emptyTotals();
	for (const e of entries) {
		const food = foodById.get(e.food_id);
		if (!food) continue;
		const t = entryTotals(e.quantity, food, valuesByFood.get(e.food_id) ?? [], keyById);
		total.energy_kcal += t.energy_kcal;
		total.protein_mg += t.protein_mg;
		total.carb_mg += t.carb_mg;
		total.fat_mg += t.fat_mg;
		total.fiber_mg += t.fiber_mg;
		for (const [k, v] of Object.entries(t.micros)) total.micros[k] = (total.micros[k] ?? 0) + v;
	}
	return total;
}

/** mg → grams, one decimal (display only). */
export function mgToG(mg: number): number {
	return Math.round(mg / 100) / 10;
}

/** Percent of a goal reached, floored, capped at 100 (null goal → null). */
export function goalPct(current: number, goal: number | null | undefined): number | null {
	if (!goal || goal <= 0) return null;
	return Math.min(100, Math.floor((100 * current) / goal));
}
