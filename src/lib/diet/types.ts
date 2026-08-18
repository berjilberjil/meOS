import type { Meal } from '../nutrition/types';

export type { Meal };

export interface DietWeek {
	id: string;
	user_id: string;
	week_start: string; // Monday, YYYY-MM-DD
	created_at: string;
	updated_at: string;
}

export interface DietSlot {
	id: string;
	user_id: string;
	week_id: string;
	weekday: number; // 0=Mon … 6=Sun
	meal: Meal;
	food_id: string;
	quantity: number;
	sort_order: number;
	created_at: string;
}

export interface SlotFoodInput {
	food_id: string;
	quantity: number;
}

export interface PlannedLogInput {
	food_id: string;
	quantity: number;
	meal: Meal;
	logged_on: string;
}
