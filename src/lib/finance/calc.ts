import type { Transaction, Category, Cadence } from './types';
import { advanceDate } from './dates';

export interface BudgetLine {
	category_id: string;
	name: string;
	spent_paise: number;
	budget_paise: number;
}

export function balanceDelta(t: Transaction, accountId: string): number {
	if (t.type === 'income' && t.account_id === accountId) return t.amount_paise;
	if (t.type === 'expense' && t.account_id === accountId) return -t.amount_paise;
	if (t.type === 'transfer') {
		let d = 0;
		if (t.account_id === accountId) d -= t.amount_paise;
		if (t.transfer_account_id === accountId) d += t.amount_paise;
		return d;
	}
	return 0;
}

export function balanceFromTransactions(openingPaise: number, txns: Transaction[], accountId: string): number {
	return txns.reduce((bal, t) => bal + balanceDelta(t, accountId), openingPaise);
}

export function budgetRollup(categories: Category[], monthTxns: Transaction[]): BudgetLine[] {
	return categories
		.filter((c) => c.kind === 'expense')
		.map((c) => ({
			category_id: c.id,
			name: c.name,
			spent_paise: monthTxns
				.filter((t) => t.type === 'expense' && t.category_id === c.id)
				.reduce((sum, t) => sum + t.amount_paise, 0),
			budget_paise: c.monthly_budget_paise
		}));
}

export function catchUpOccurrences(
	nextRunOn: string,
	cadence: Cadence,
	intervalDays: number | null,
	today: string
): { dates: string[]; nextRunOn: string } {
	const dates: string[] = [];
	let cursor = nextRunOn;
	// guard against a misconfigured custom interval looping forever
	let guard = 0;
	while (cursor <= today && guard < 1000) {
		dates.push(cursor);
		cursor = advanceDate(cursor, cadence, intervalDays);
		guard++;
	}
	return { dates, nextRunOn: cursor };
}
