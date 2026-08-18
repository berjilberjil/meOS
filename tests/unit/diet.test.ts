import { describe, it, expect } from 'vitest';
import { weekStartMonday, shiftWeek, weekdayIndex, WEEKDAY_LABELS } from '$lib/diet/week';
import {
	replaceSlotFoods,
	addSlotFood,
	removeSlotFood,
	clearSlot,
	plannedMealToLogEntries,
	slotsForMeal,
	planDayTotals
} from '$lib/diet/plan';
import type { DietSlot } from '$lib/diet/types';
import { entryTotals, nutrientKeyById, groupValuesByFood } from '$lib/nutrition/calc';
import type { FoodItem, FoodNutrientValue, Nutrient } from '$lib/nutrition/types';

describe('weekStartMonday', () => {
	it('returns the same day when the date is already Monday', () => {
		expect(weekStartMonday('2026-08-17')).toBe('2026-08-17');
	});

	it('rolls Wednesday back to that week’s Monday', () => {
		expect(weekStartMonday('2026-08-19')).toBe('2026-08-17');
	});

	it('rolls Sunday back to the previous Monday, not the next', () => {
		expect(weekStartMonday('2026-08-23')).toBe('2026-08-17');
	});
});

describe('shiftWeek / weekdayIndex', () => {
	it('shifts a Monday forward and backward by 7 days', () => {
		expect(shiftWeek('2026-08-17', 1)).toBe('2026-08-24');
		expect(shiftWeek('2026-08-17', -1)).toBe('2026-08-10');
	});

	it('maps ISO dates to Mon=0 … Sun=6', () => {
		expect(weekdayIndex('2026-08-17')).toBe(0);
		expect(weekdayIndex('2026-08-19')).toBe(2);
		expect(weekdayIndex('2026-08-23')).toBe(6);
	});

	it('exposes seven short weekday labels starting Monday', () => {
		expect(WEEKDAY_LABELS).toEqual(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
	});
});

function slot(p: Partial<DietSlot>): DietSlot {
	return {
		id: p.id ?? 's',
		user_id: p.user_id ?? 'u',
		week_id: p.week_id ?? 'w',
		weekday: p.weekday ?? 0,
		meal: p.meal ?? 'breakfast',
		food_id: p.food_id ?? 'chap',
		quantity: p.quantity ?? 1,
		sort_order: p.sort_order ?? 0,
		created_at: p.created_at ?? ''
	};
}

describe('replaceSlotFoods', () => {
	it('replaces only the targeted weekday+meal and keeps other slots', () => {
		const current = [
			slot({ id: 'a', weekday: 0, meal: 'breakfast', food_id: 'idli', quantity: 2 }),
			slot({ id: 'b', weekday: 0, meal: 'lunch', food_id: 'rice', quantity: 1 }),
			slot({ id: 'c', weekday: 1, meal: 'breakfast', food_id: 'oats', quantity: 1 })
		];
		const next = replaceSlotFoods(current, 0, 'breakfast', [
			{ food_id: 'dosa', quantity: 1 },
			{ food_id: 'chutney', quantity: 1 }
		]);
		expect(slotsForMeal(next, 0, 'breakfast').map((s) => s.food_id)).toEqual(['dosa', 'chutney']);
		expect(slotsForMeal(next, 0, 'lunch')).toHaveLength(1);
		expect(slotsForMeal(next, 1, 'breakfast')).toHaveLength(1);
	});

	it('assigns sort_order in input order', () => {
		const next = replaceSlotFoods([], 3, 'dinner', [
			{ food_id: 'chicken', quantity: 1 },
			{ food_id: 'rice', quantity: 0.5 }
		]);
		expect(next.map((s) => s.sort_order)).toEqual([0, 1]);
	});
});

describe('add / remove / clear slot foods', () => {
	it('appends a food to an existing meal with the next sort_order', () => {
		const current = [slot({ weekday: 0, meal: 'snack', food_id: 'whey', sort_order: 0 })];
		const next = addSlotFood(current, 0, 'snack', { food_id: 'banana', quantity: 1 });
		expect(next.map((s) => s.food_id)).toEqual(['whey', 'banana']);
		expect(next[1].sort_order).toBe(1);
	});

	it('removes one food row by id and leaves the rest', () => {
		const current = [
			slot({ id: 'keep', weekday: 2, meal: 'lunch', food_id: 'rice' }),
			slot({ id: 'gone', weekday: 2, meal: 'lunch', food_id: 'papad' })
		];
		expect(removeSlotFood(current, 'gone').map((s) => s.id)).toEqual(['keep']);
	});

	it('clears every food in one meal without touching other meals', () => {
		const current = [
			slot({ weekday: 0, meal: 'breakfast', food_id: 'idli' }),
			slot({ weekday: 0, meal: 'lunch', food_id: 'rice' })
		];
		expect(clearSlot(current, 0, 'breakfast')).toEqual([current[1]]);
	});
});

describe('plannedMealToLogEntries', () => {
	it('copies a planned meal into food-log payloads for a given date', () => {
		const slots = [
			slot({ weekday: 2, meal: 'lunch', food_id: 'rice', quantity: 1 }),
			slot({ weekday: 2, meal: 'lunch', food_id: 'sambar', quantity: 1 }),
			slot({ weekday: 2, meal: 'dinner', food_id: 'chicken', quantity: 1 })
		];
		const logs = plannedMealToLogEntries(slots, 2, 'lunch', '2026-08-19');
		expect(logs).toEqual([
			{ food_id: 'rice', quantity: 1, meal: 'lunch', logged_on: '2026-08-19' },
			{ food_id: 'sambar', quantity: 1, meal: 'lunch', logged_on: '2026-08-19' }
		]);
	});

	it('returns an empty list when that meal has no planned foods', () => {
		expect(plannedMealToLogEntries([], 0, 'breakfast', '2026-08-17')).toEqual([]);
	});
});

describe('planDayTotals', () => {
	const nutrients: Nutrient[] = [
		{ id: 'np', key: 'protein', label: 'Protein', unit: 'mg', nutrient_group: 'macro', sort_order: 1 }
	];
	const keyById = nutrientKeyById(nutrients);
	const chapati: FoodItem = {
		id: 'chap',
		user_id: null,
		name: 'Chapati',
		category: 'grain',
		default_serving_label: '1 chapati',
		serving_grams: 40,
		energy_kcal: 120,
		created_at: '',
		updated_at: ''
	};
	const values: FoodNutrientValue[] = [{ food_id: 'chap', nutrient_id: 'np', amount: 3000 }];
	const foodById = new Map([['chap', chapati]]);
	const valuesByFood = groupValuesByFood(values);

	it('sums planned foods for one weekday', () => {
		const slots = [
			slot({ weekday: 0, meal: 'breakfast', food_id: 'chap', quantity: 2 }),
			slot({ weekday: 0, meal: 'dinner', food_id: 'chap', quantity: 1 }),
			slot({ weekday: 1, meal: 'breakfast', food_id: 'chap', quantity: 9 })
		];
		const t = planDayTotals(slots, 0, foodById, valuesByFood, keyById);
		expect(t.energy_kcal).toBe(360);
		expect(t.protein_mg).toBe(9000);
	});

	it('matches entryTotals for a single planned food', () => {
		const slots = [slot({ weekday: 4, meal: 'snack', food_id: 'chap', quantity: 0.5 })];
		const t = planDayTotals(slots, 4, foodById, valuesByFood, keyById);
		expect(t).toEqual(entryTotals(0.5, chapati, values, keyById));
	});
});
