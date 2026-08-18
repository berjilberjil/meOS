import { randomUUID } from 'node:crypto';
import seedFoods from './foods.json' with { type: 'json' };

export type Macros = { calories: number; protein: number; carbs: number; fiber: number; fats: number };
export type Food = {
	id: string;
	name: string;
	category: string;
	servingLabel: string;
	perServing: Macros;
	vitamins?: string;
	isDefault: boolean;
};
export type PlanItem = { id: string; foodId: string; quantity: number };
export type MealKey = 'breakfast' | 'lunch' | 'dinner' | 'snacks';
export type MealLog = { meals: Record<string, PlanItem[]>; skipped: string[] };
export type NutritionState = {
	customFoods: Food[];
	log: Record<string, MealLog>;
	mealPlan: Record<string, Partial<Record<MealKey, PlanItem[]>>>;
};

export const MEALS: MealKey[] = ['breakfast', 'lunch', 'dinner', 'snacks'];
export const WEEKDAYS = ['0', '1', '2', '3', '4', '5', '6'] as const;
export const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;

export function emptyNutrition(): NutritionState {
	return { customFoods: [], log: {}, mealPlan: {} };
}

export function normalizeMeal(raw: string): MealKey {
	const m = raw.trim().toLowerCase();
	if (m === 'snack' || m === 'snacks') return 'snacks';
	if (m === 'breakfast' || m === 'lunch' || m === 'dinner') return m;
	throw new Error(`unknown meal: ${raw}`);
}

/** Native app: 0=Sun … 6=Sat. */
export function weekdayFromDate(iso: string): string {
	const [y, m, d] = iso.split('-').map(Number);
	const dt = new Date(Date.UTC(y, (m ?? 1) - 1, d ?? 1));
	return String(dt.getUTCDay());
}

export function todayIso(now = new Date()): string {
	const y = now.getFullYear();
	const m = String(now.getMonth() + 1).padStart(2, '0');
	const d = String(now.getDate()).padStart(2, '0');
	return `${y}-${m}-${d}`;
}

export function catalog(custom: Food[] = []): Food[] {
	const byId = new Map<string, Food>();
	for (const f of seedFoods as Food[]) byId.set(f.id, f);
	for (const f of custom) byId.set(f.id, f);
	return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function foodById(id: string, custom: Food[] = []): Food | undefined {
	return catalog(custom).find((f) => f.id === id);
}

export function searchFoods(query: string, limit = 12, custom: Food[] = []): Food[] {
	const q = query.trim().toLowerCase();
	const all = catalog(custom);
	const hits = q ? all.filter((f) => f.name.toLowerCase().includes(q)) : all;
	return hits.slice(0, limit);
}

export function item(foodId: string, quantity: number): PlanItem {
	return { id: randomUUID(), foodId, quantity };
}

export function setSlot(
	n: NutritionState,
	weekday: string,
	meal: string,
	foods: Array<{ foodId: string; quantity: number }>
): NutritionState {
	const m = normalizeMeal(meal);
	const day = { ...(n.mealPlan[weekday] ?? {}) };
	day[m] = foods.map((f) => item(f.foodId, f.quantity));
	return { ...n, mealPlan: { ...n.mealPlan, [weekday]: day } };
}

export function addSlotFood(
	n: NutritionState,
	weekday: string,
	meal: string,
	foodId: string,
	quantity: number
): NutritionState {
	const m = normalizeMeal(meal);
	const day = { ...(n.mealPlan[weekday] ?? {}) };
	day[m] = [...(day[m] ?? []), item(foodId, quantity)];
	return { ...n, mealPlan: { ...n.mealPlan, [weekday]: day } };
}

export function removeSlotFood(n: NutritionState, itemId: string): NutritionState {
	const mealPlan: NutritionState['mealPlan'] = {};
	for (const [wd, day] of Object.entries(n.mealPlan)) {
		const next: Partial<Record<MealKey, PlanItem[]>> = {};
		for (const meal of MEALS) {
			const kept = (day[meal] ?? []).filter((x) => x.id !== itemId);
			if (kept.length) next[meal] = kept;
		}
		if (Object.keys(next).length) mealPlan[wd] = next;
	}
	return { ...n, mealPlan };
}

export function clearSlot(n: NutritionState, weekday: string, meal: string): NutritionState {
	const m = normalizeMeal(meal);
	const day = { ...(n.mealPlan[weekday] ?? {}) };
	delete day[m];
	const mealPlan = { ...n.mealPlan };
	if (Object.keys(day).length) mealPlan[weekday] = day;
	else delete mealPlan[weekday];
	return { ...n, mealPlan };
}

export function clearWeek(n: NutritionState): NutritionState {
	return { ...n, mealPlan: {} };
}

export function logFood(
	n: NutritionState,
	date: string,
	meal: string,
	foodId: string,
	quantity: number
): NutritionState {
	const m = normalizeMeal(meal);
	const day = n.log[date] ?? { meals: {}, skipped: [] };
	const meals = { ...day.meals, [m]: [...(day.meals[m] ?? []), item(foodId, quantity)] };
	const skipped = day.skipped.filter((s) => s !== m);
	return { ...n, log: { ...n.log, [date]: { meals, skipped } } };
}

export function logPlannedMeal(n: NutritionState, date: string, weekday: string, meal: string): NutritionState {
	const m = normalizeMeal(meal);
	const planned = n.mealPlan[weekday]?.[m] ?? [];
	if (!planned.length) return n;
	const day = n.log[date] ?? { meals: {}, skipped: [] };
	const copied = planned.map((p) => item(p.foodId, p.quantity));
	const meals = { ...day.meals, [m]: copied };
	const skipped = day.skipped.filter((s) => s !== m);
	return { ...n, log: { ...n.log, [date]: { meals, skipped } } };
}

export function deleteLogItem(n: NutritionState, logId: string): NutritionState {
	const log: NutritionState['log'] = {};
	for (const [date, day] of Object.entries(n.log)) {
		const meals: Record<string, PlanItem[]> = {};
		for (const [meal, items] of Object.entries(day.meals)) {
			const kept = items.filter((x) => x.id !== logId);
			if (kept.length) meals[meal] = kept;
		}
		log[date] = { meals, skipped: day.skipped };
	}
	return { ...n, log };
}

export function totalsForItems(items: PlanItem[], custom: Food[] = []): Macros {
	const zero: Macros = { calories: 0, protein: 0, carbs: 0, fiber: 0, fats: 0 };
	return items.reduce((acc, it) => {
		const f = foodById(it.foodId, custom);
		if (!f) return acc;
		const q = it.quantity;
		return {
			calories: acc.calories + f.perServing.calories * q,
			protein: acc.protein + f.perServing.protein * q,
			carbs: acc.carbs + f.perServing.carbs * q,
			fiber: acc.fiber + f.perServing.fiber * q,
			fats: acc.fats + f.perServing.fats * q
		};
	}, zero);
}

export function planItems(n: NutritionState, weekday: string, meal: string): PlanItem[] {
	return n.mealPlan[weekday]?.[normalizeMeal(meal)] ?? [];
}

export function upsertCustomFood(n: NutritionState, food: Omit<Food, 'id' | 'isDefault'> & { id?: string }): NutritionState {
	const id = food.id ?? randomUUID();
	const next: Food = { ...food, id, isDefault: false };
	const rest = n.customFoods.filter((f) => f.id !== id);
	return { ...n, customFoods: [next, ...rest] };
}
