import { supabaseBrowser } from '$lib/supabase/client';
import { createDietStore } from './store';

export function dietStore() {
	return createDietStore(supabaseBrowser() as never);
}

export type { DietStore, FoodHit, WeekPlanView } from './store';
export type { DietSlot, DietWeek, SlotFoodInput } from './types';
export {
	WEEKDAY_LABELS,
	dateForWeekday,
	shiftWeek,
	weekStartMonday,
	weekdayIndex
} from './week';
export {
	addSlotFood,
	clearSlot,
	planDayTotals,
	plannedMealToLogEntries,
	removeSlotFood,
	replaceSlotFoods,
	slotsForMeal
} from './plan';
