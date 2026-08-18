import { dailyTotals, type FoodTotals } from '../nutrition/calc';
import type { FoodItem, FoodLogEntry, FoodNutrientValue, Meal } from '../nutrition/types';
import type { DietSlot, PlannedLogInput, SlotFoodInput } from './types';

export function slotsForMeal(slots: DietSlot[], weekday: number, meal: Meal): DietSlot[] {
	return slots
		.filter((s) => s.weekday === weekday && s.meal === meal)
		.sort((a, b) => a.sort_order - b.sort_order);
}

export function replaceSlotFoods(
	slots: DietSlot[],
	weekday: number,
	meal: Meal,
	foods: SlotFoodInput[]
): DietSlot[] {
	const kept = slots.filter((s) => !(s.weekday === weekday && s.meal === meal));
	const week_id = slots[0]?.week_id ?? '';
	const added: DietSlot[] = foods.map((f, i) => ({
		id: '',
		user_id: slots[0]?.user_id ?? '',
		week_id,
		weekday,
		meal,
		food_id: f.food_id,
		quantity: f.quantity,
		sort_order: i,
		created_at: ''
	}));
	return [...kept, ...added];
}

export function addSlotFood(
	slots: DietSlot[],
	weekday: number,
	meal: Meal,
	food: SlotFoodInput
): DietSlot[] {
	const existing = slotsForMeal(slots, weekday, meal);
	const nextOrder = existing.reduce((m, s) => Math.max(m, s.sort_order + 1), 0);
	return [
		...slots,
		{
			id: '',
			user_id: slots[0]?.user_id ?? '',
			week_id: slots[0]?.week_id ?? '',
			weekday,
			meal,
			food_id: food.food_id,
			quantity: food.quantity,
			sort_order: nextOrder,
			created_at: ''
		}
	];
}

export function removeSlotFood(slots: DietSlot[], id: string): DietSlot[] {
	return slots.filter((s) => s.id !== id);
}

export function clearSlot(slots: DietSlot[], weekday: number, meal: Meal): DietSlot[] {
	return slots.filter((s) => !(s.weekday === weekday && s.meal === meal));
}

export function plannedMealToLogEntries(
	slots: DietSlot[],
	weekday: number,
	meal: Meal,
	loggedOn: string
): PlannedLogInput[] {
	return slotsForMeal(slots, weekday, meal).map((s) => ({
		food_id: s.food_id,
		quantity: s.quantity,
		meal,
		logged_on: loggedOn
	}));
}

export function planDayTotals(
	slots: DietSlot[],
	weekday: number,
	foodById: Map<string, FoodItem>,
	valuesByFood: Map<string, FoodNutrientValue[]>,
	keyById: Map<string, string>
): FoodTotals {
	const daySlots = slots.filter((s) => s.weekday === weekday);
	const asEntries = daySlots.map(
		(s) =>
			({
				id: s.id,
				user_id: '',
				logged_on: '',
				food_id: s.food_id,
				quantity: s.quantity,
				meal: s.meal,
				notes: null,
				created_at: '',
				updated_at: ''
			}) satisfies FoodLogEntry
	);
	return dailyTotals(asEntries, foodById, valuesByFood, keyById);
}
