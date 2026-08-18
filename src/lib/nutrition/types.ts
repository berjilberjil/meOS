// Food & nutrition types. Nutrient amounts are integers in the nutrient's unit
// (mg/mcg); energy in kcal. Serving quantity is a decimal serving-count.

export type Meal = 'breakfast' | 'lunch' | 'dinner' | 'snack';
export type NutrientUnit = 'kcal' | 'mg' | 'mcg' | 'g_int';
export type NutrientGroup = 'macro' | 'vitamin' | 'mineral' | 'other';

export interface Nutrient {
	id: string;
	key: string;
	label: string;
	unit: NutrientUnit;
	nutrient_group: NutrientGroup;
	sort_order: number;
}

export interface FoodItem {
	id: string;
	user_id: string | null; // null = shared/global catalog
	name: string;
	category: string;
	default_serving_label: string;
	serving_grams: number;
	energy_kcal: number;
	created_at: string;
	updated_at: string;
}

export interface FoodNutrientValue {
	food_id: string;
	nutrient_id: string;
	amount: number; // integer, in the nutrient's unit, per default serving
}

export interface FoodLogEntry {
	id: string;
	user_id: string;
	logged_on: string; // 'YYYY-MM-DD'
	food_id: string;
	quantity: number; // servings (may be fractional)
	meal: Meal | null;
	notes: string | null;
	created_at: string;
	updated_at: string;
}

export interface NutritionGoals {
	energy_kcal: number | null;
	protein_mg: number | null;
	carb_mg: number | null;
	fat_mg: number | null;
	fiber_mg: number | null;
}

export const MEALS: Meal[] = ['breakfast', 'lunch', 'dinner', 'snack'];

export const FOOD_CATEGORIES = [
	'grain',
	'protein',
	'dairy',
	'fruit',
	'vegetable',
	'snack',
	'beverage',
	'prepared',
	'other'
];
