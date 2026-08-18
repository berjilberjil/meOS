import { describe, expect, test } from 'bun:test';
import {
	addSlotFood,
	clearSlot,
	clearWeek,
	emptyNutrition,
	logFood,
	removeSlotFood,
	searchFoods,
	setSlot,
	totalsForItems,
	weekdayFromDate,
	normalizeMeal
} from '../src/plan';

describe('meal plan', () => {
	test('setSlot replaces one meal and leaves others', () => {
		let n = emptyNutrition();
		n = setSlot(n, '2', 'breakfast', [{ foodId: 'seed-food-22', quantity: 1 }]);
		n = setSlot(n, '2', 'lunch', [{ foodId: 'seed-food-1', quantity: 2 }]);
		n = setSlot(n, '2', 'breakfast', [{ foodId: 'seed-food-12', quantity: 1 }]);
		expect(n.mealPlan['2']!.breakfast).toHaveLength(1);
		expect(n.mealPlan['2']!.breakfast[0]!.foodId).toBe('seed-food-12');
		expect(n.mealPlan['2']!.lunch[0]!.foodId).toBe('seed-food-1');
	});

	test('addSlotFood appends without clearing', () => {
		let n = emptyNutrition();
		n = addSlotFood(n, '0', 'snacks', 'seed-food-22', 1);
		n = addSlotFood(n, '0', 'snacks', 'seed-food-12', 2);
		expect(n.mealPlan['0']!.snacks.map((x) => x.foodId)).toEqual(['seed-food-22', 'seed-food-12']);
	});

	test('clearSlot and clearWeek empty the grid', () => {
		let n = emptyNutrition();
		n = setSlot(n, '1', 'dinner', [{ foodId: 'seed-food-1', quantity: 1 }]);
		n = setSlot(n, '3', 'lunch', [{ foodId: 'seed-food-2', quantity: 1 }]);
		n = clearSlot(n, '1', 'dinner');
		expect(n.mealPlan['1']?.dinner ?? []).toEqual([]);
		n = clearWeek(n);
		expect(n.mealPlan).toEqual({});
	});

	test('removeSlotFood drops one planned row by id', () => {
		let n = emptyNutrition();
		n = addSlotFood(n, '6', 'lunch', 'seed-food-1', 1);
		const id = n.mealPlan['6']!.lunch[0]!.id;
		n = removeSlotFood(n, id);
		expect(n.mealPlan['6']?.lunch ?? []).toEqual([]);
	});

	test('logFood writes the daily log not the plan', () => {
		let n = emptyNutrition();
		n = logFood(n, '2026-08-18', 'breakfast', 'seed-food-22', 1);
		expect(n.log['2026-08-18']!.meals.breakfast[0]!.foodId).toBe('seed-food-22');
		expect(n.mealPlan).toEqual({});
	});

	test('weekdayFromDate is Sunday=0 matching the native app', () => {
		expect(weekdayFromDate('2026-08-16')).toBe('0'); // Sunday
		expect(weekdayFromDate('2026-08-18')).toBe('2'); // Tuesday
	});

	test('normalizeMeal maps snack to snacks', () => {
		expect(normalizeMeal('snack')).toBe('snacks');
		expect(normalizeMeal('SNACKS')).toBe('snacks');
	});

	test('searchFoods hits seed catalog by substring', () => {
		const hits = searchFoods('oats', 5);
		expect(hits.some((f) => f.id === 'seed-food-22')).toBe(true);
		expect(hits[0]!.name.toLowerCase()).toContain('oat');
	});

	test('totalsForItems scales servings', () => {
		const t = totalsForItems([{ id: 'x', foodId: 'seed-food-22', quantity: 2 }]);
		expect(t.calories).toBe(304);
		expect(t.protein).toBe(10);
	});
});
