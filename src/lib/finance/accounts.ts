import { SupabaseRepository } from '$lib/data/repository';
import type { Account, Transaction } from './types';
import { balanceFromTransactions } from './calc';
import { forAccountTxns } from './transactions';

export const accountsRepo = new SupabaseRepository<Account>('accounts');

export function netWorth(accounts: Account[]): number {
	return accounts.filter((a) => !a.archived).reduce((s, a) => s + a.balance_paise, 0);
}

export function reconcile(account: Account, txns: Transaction[]): { expected: number; drift: number } {
	const expected = balanceFromTransactions(account.opening_balance_paise, txns, account.id);
	return { expected, drift: expected - account.balance_paise };
}

export async function reconcileAccount(accountId: string): Promise<{ repaired: boolean; balance: number }> {
	const account = await accountsRepo.get(accountId);
	if (!account) return { repaired: false, balance: 0 };
	const txns = await forAccountTxns(accountId);
	const { expected, drift } = reconcile(account, txns);
	if (drift !== 0) {
		await accountsRepo.update(accountId, { balance_paise: expected } as Partial<Account>);
		return { repaired: true, balance: expected };
	}
	return { repaired: false, balance: expected };
}

export async function reconcileAll(): Promise<number> {
	const accounts = await accountsRepo.list();
	let repaired = 0;
	for (const a of accounts) {
		const r = await reconcileAccount(a.id);
		if (r.repaired) repaired++;
	}
	return repaired;
}
