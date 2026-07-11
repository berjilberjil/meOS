import { describe, it, expect } from 'vitest';
import {
	entryTotals,
	dailyTotals,
	nutrientKeyById,
	groupValuesByFood,
	mgToG,
	goalPct
} from '$lib/nutrition/calc';
import type { FoodItem, FoodLogEntry, FoodNutrientValue, Nutrient } from '$lib/nutrition/types';

const nutrients: Nutrient[] = [
	{ id: 'np', key: 'protein', label: 'Protein', unit: 'mg', nutrient_group: 'macro', sort_order: 1 },
	{ id: 'nc', key: 'carb', label: 'Carb', unit: 'mg', nutrient_group: 'macro', sort_order: 2 },
	{ id: 'nf', key: 'fat', label: 'Fat', unit: 'mg', nutrient_group: 'macro', sort_order: 3 },
	{ id: 'nfi', key: 'fiber', label: 'Fiber', unit: 'mg', nutrient_group: 'macro', sort_order: 4 },
	{ id: 'nca', key: 'calcium', label: 'Calcium', unit: 'mg', nutrient_group: 'mineral', sort_order: 30 }
];
const keyById = nutrientKeyById(nutrients);

function food(p: Partial<FoodItem>): FoodItem {
	return {
		id: 'f', user_id: null, name: 'x', category: 'grain', default_serving_label: '1',
		serving_grams: 40, energy_kcal: 0, created_at: '', updated_at: '', ...p
	};
}
function entry(p: Partial<FoodLogEntry>): FoodLogEntry {
	return {
		id: 'e', user_id: 'u', logged_on: '2026-07-11', food_id: 'f', quantity: 1,
		meal: null, notes: null, created_at: '', updated_at: '', ...p
	};
}

const chapati = food({ id: 'chap', energy_kcal: 120 });
const chapatiValues: FoodNutrientValue[] = [
	{ food_id: 'chap', nutrient_id: 'np', amount: 3000 },
	{ food_id: 'chap', nutrient_id: 'nc', amount: 20000 },
	{ food_id: 'chap', nutrient_id: 'nf', amount: 3000 },
	{ food_id: 'chap', nutrient_id: 'nfi', amount: 2000 },
	{ food_id: 'chap', nutrient_id: 'nca', amount: 15 }
];

describe('entryTotals — 5 chapatis', () => {
	const t = entryTotals(5, chapati, chapatiValues, keyById);
	it('multiplies energy + macros by quantity', () => {
		expect(t.energy_kcal).toBe(600);
		expect(t.protein_mg).toBe(15000); // 15 g
		expect(t.carb_mg).toBe(100000);
		expect(t.fat_mg).toBe(15000);
		expect(t.fiber_mg).toBe(10000);
	});
	it('non-macro nutrients land in micros by key', () => {
		expect(t.micros).toEqual({ calcium: 75 });
	});
	it('handles fractional quantity', () => {
		expect(entryTotals(0.5, chapati, chapatiValues, keyById).energy_kcal).toBe(60);
	});
});

describe('dailyTotals', () => {
	const rice = food({ id: 'rice', energy_kcal: 200 });
	const riceValues: FoodNutrientValue[] = [
		{ food_id: 'rice', nutrient_id: 'np', amount: 4000 },
		{ food_id: 'rice', nutrient_id: 'nc', amount: 44000 }
	];
	const foodById = new Map([
		['chap', chapati],
		['rice', rice]
	]);
	const valuesByFood = groupValuesByFood([...chapatiValues, ...riceValues]);
	const entries = [
		entry({ food_id: 'chap', quantity: 2 }),
		entry({ food_id: 'rice', quantity: 1 })
	];
	const t = dailyTotals(entries, foodById, valuesByFood, keyById);
	it('sums across entries', () => {
		expect(t.energy_kcal).toBe(440); // 2*120 + 200
		expect(t.protein_mg).toBe(10000); // 2*3000 + 4000
		expect(t.carb_mg).toBe(84000); // 2*20000 + 44000
		expect(t.micros.calcium).toBe(30); // 2*15 (rice has none)
	});
	it('skips entries whose food is missing', () => {
		const t2 = dailyTotals([entry({ food_id: 'ghost' })], foodById, valuesByFood, keyById);
		expect(t2.energy_kcal).toBe(0);
	});
});

describe('display helpers', () => {
	it('mgToG gives grams with one decimal', () => {
		expect(mgToG(15000)).toBe(15);
		expect(mgToG(3200)).toBe(3.2);
	});
	it('goalPct floors and caps, null when no goal', () => {
		expect(goalPct(600, 2200)).toBe(27);
		expect(goalPct(3000, 2200)).toBe(100);
		expect(goalPct(600, null)).toBeNull();
		expect(goalPct(600, 0)).toBeNull();
	});
});
