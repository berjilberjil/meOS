import { SupabaseRepository } from '$lib/data/repository';
import type { Category, CategoryKind } from './types';

export const categoriesRepo = new SupabaseRepository<Category>('categories');

export const DEFAULT_CATEGORIES: { name: string; kind: CategoryKind; icon: string; color: string }[] = [
	{ name: 'Salary', kind: 'income', icon: 'wallet', color: 'oklch(0.72 0.15 150)' },
	{ name: 'Other income', kind: 'income', icon: 'plus', color: 'oklch(0.72 0.12 200)' },
	{ name: 'Groceries', kind: 'expense', icon: 'shopping-cart', color: 'oklch(0.7 0.15 60)' },
	{ name: 'Rent', kind: 'expense', icon: 'home', color: 'oklch(0.65 0.16 25)' },
	{ name: 'Food & dining', kind: 'expense', icon: 'utensils', color: 'oklch(0.7 0.16 40)' },
	{ name: 'Transport', kind: 'expense', icon: 'car', color: 'oklch(0.68 0.14 280)' },
	{ name: 'Bills & utilities', kind: 'expense', icon: 'zap', color: 'oklch(0.7 0.13 100)' },
	{ name: 'Subscriptions', kind: 'expense', icon: 'repeat', color: 'oklch(0.66 0.15 320)' },
	{ name: 'Health', kind: 'expense', icon: 'heart', color: 'oklch(0.68 0.16 10)' },
	{ name: 'Investments', kind: 'expense', icon: 'trending-up', color: 'oklch(0.7 0.14 170)' },
	{ name: 'Shopping', kind: 'expense', icon: 'shopping-bag', color: 'oklch(0.69 0.15 330)' },
	{ name: 'Misc', kind: 'expense', icon: 'circle', color: 'oklch(0.6 0.02 260)' }
];

export async function seedDefaultCategories(): Promise<boolean> {
	const existing = await categoriesRepo.list();
	if (existing.length > 0) return false;
	for (const c of DEFAULT_CATEGORIES) {
		await categoriesRepo.create({ ...c, monthly_budget_paise: 0 } as Partial<Category>);
	}
	return true;
}
