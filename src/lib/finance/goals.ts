import { SupabaseRepository } from '$lib/data/repository';
import { createTransaction } from './transactions';
import type { SavingsGoal } from './types';

export const goalsRepo = new SupabaseRepository<SavingsGoal>('savings_goals');

export async function contributeToGoal(goal: SavingsGoal, amountPaise: number, accountId: string): Promise<void> {
	await createTransaction({
		account_id: accountId,
		type: 'expense',
		amount_paise: amountPaise,
		category_id: null,
		note: `Goal: ${goal.name}`
	});
	await goalsRepo.update(goal.id, { saved_paise: goal.saved_paise + amountPaise } as Partial<SavingsGoal>);
}
