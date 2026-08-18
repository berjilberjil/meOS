import { describe, it, expect } from 'vitest';
import { balanceDelta, balanceFromTransactions, budgetRollup, catchUpOccurrences } from '$lib/finance/calc';
import { budgetTotals } from '$lib/finance/budgets';
import type { Transaction, Category } from '$lib/finance/types';

function txn(p: Partial<Transaction>): Transaction {
	return {
		id: 't', user_id: 'u', account_id: 'A', category_id: null, type: 'expense',
		amount_paise: 0, transfer_account_id: null, note: null, occurred_on: '2026-06-01',
		recurring_id: null, created_at: '', updated_at: '', ...p
	};
}

describe('balanceDelta', () => {
	it('income adds, expense subtracts for the owning account', () => {
		expect(balanceDelta(txn({ type: 'income', amount_paise: 5000, account_id: 'A' }), 'A')).toBe(5000);
		expect(balanceDelta(txn({ type: 'expense', amount_paise: 5000, account_id: 'A' }), 'A')).toBe(-5000);
	});
	it('transfer leaves source and enters destination, netting to zero', () => {
		const t = txn({ type: 'transfer', amount_paise: 5000, account_id: 'A', transfer_account_id: 'B' });
		expect(balanceDelta(t, 'A')).toBe(-5000);
		expect(balanceDelta(t, 'B')).toBe(5000);
		expect(balanceDelta(t, 'A') + balanceDelta(t, 'B')).toBe(0);
	});
});

describe('balanceFromTransactions', () => {
	it('opening + deltas', () => {
		const txns = [
			txn({ type: 'income', amount_paise: 10000, account_id: 'A' }),
			txn({ type: 'expense', amount_paise: 3000, account_id: 'A' }),
			txn({ type: 'transfer', amount_paise: 2000, account_id: 'A', transfer_account_id: 'B' })
		];
		expect(balanceFromTransactions(100000, txns, 'A')).toBe(105000);
		expect(balanceFromTransactions(0, txns, 'B')).toBe(2000);
	});
});

describe('budgetRollup', () => {
	it('sums expense txns per category vs its budget', () => {
		const cats: Category[] = [
			{ id: 'c1', user_id: 'u', name: 'Food', kind: 'expense', icon: null, color: null, monthly_budget_paise: 500000, created_at: '', updated_at: '' },
			{ id: 'c2', user_id: 'u', name: 'Salary', kind: 'income', icon: null, color: null, monthly_budget_paise: 0, created_at: '', updated_at: '' }
		];
		const txns = [
			txn({ type: 'expense', amount_paise: 120000, category_id: 'c1' }),
			txn({ type: 'expense', amount_paise: 80000, category_id: 'c1' }),
			txn({ type: 'income', amount_paise: 9000000, category_id: 'c2' })
		];
		const lines = budgetRollup(cats, txns);
		expect(lines).toEqual([{ category_id: 'c1', name: 'Food', spent_paise: 200000, budget_paise: 500000 }]);
	});
});

describe('catchUpOccurrences', () => {
	it('returns nothing when next run is in the future', () => {
		expect(catchUpOccurrences('2026-07-01', 'monthly', null, '2026-06-26')).toEqual({ dates: [], nextRunOn: '2026-07-01' });
	});
	it('posts every missed monthly occurrence up to today and advances', () => {
		const r = catchUpOccurrences('2026-04-15', 'monthly', null, '2026-06-26');
		expect(r.dates).toEqual(['2026-04-15', '2026-05-15', '2026-06-15']);
		expect(r.nextRunOn).toBe('2026-07-15');
	});
	it('is idempotent — re-running from the advanced date yields nothing', () => {
		const r2 = catchUpOccurrences('2026-07-15', 'monthly', null, '2026-06-26');
		expect(r2.dates).toEqual([]);
	});
});

describe('budgetTotals', () => {
	it('sums spent and budget across lines', () => {
		expect(
			budgetTotals([
				{ category_id: 'c1', name: 'Food', spent_paise: 200000, budget_paise: 500000 },
				{ category_id: 'c2', name: 'Rent', spent_paise: 1500000, budget_paise: 1500000 }
			])
		).toEqual({ spent_paise: 1700000, budget_paise: 2000000 });
	});
});
