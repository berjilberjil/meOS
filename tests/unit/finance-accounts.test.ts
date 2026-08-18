import { describe, it, expect } from 'vitest';
import { netWorth, reconcile } from '$lib/finance/accounts';
import type { Account, Transaction } from '$lib/finance/types';

function acct(p: Partial<Account>): Account {
	return {
		id: 'A', user_id: 'u', name: 'HDFC', type: 'bank', opening_balance_paise: 0,
		balance_paise: 0, currency: 'INR', archived: false, created_at: '', updated_at: '', ...p
	};
}
function txn(p: Partial<Transaction>): Transaction {
	return {
		id: 't', user_id: 'u', account_id: 'A', category_id: null, type: 'expense',
		amount_paise: 0, transfer_account_id: null, note: null, occurred_on: '2026-06-01',
		recurring_id: null, created_at: '', updated_at: '', ...p
	};
}

describe('netWorth', () => {
	it('sums non-archived account balances', () => {
		expect(netWorth([acct({ balance_paise: 100000 }), acct({ balance_paise: 50000 }), acct({ balance_paise: 999, archived: true })])).toBe(150000);
	});
});

describe('reconcile', () => {
	it('reports drift between cached balance and recomputed balance', () => {
		const a = acct({ id: 'A', opening_balance_paise: 100000, balance_paise: 100000 });
		const txns = [txn({ type: 'expense', amount_paise: 3000, account_id: 'A' })];
		expect(reconcile(a, txns)).toEqual({ expected: 97000, drift: -3000 });
	});
	it('zero drift when cache is correct', () => {
		const a = acct({ id: 'A', opening_balance_paise: 100000, balance_paise: 97000 });
		const txns = [txn({ type: 'expense', amount_paise: 3000, account_id: 'A' })];
		expect(reconcile(a, txns)).toEqual({ expected: 97000, drift: 0 });
	});
});
