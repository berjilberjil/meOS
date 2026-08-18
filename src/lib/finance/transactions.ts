import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import { enqueue } from '$lib/data/sync-queue';
import { balanceDelta } from './calc';
import { monthRange, todayIso } from './dates';
import type { Account, Transaction, TxnType } from './types';

export const txnRepo = new SupabaseRepository<Transaction>('transactions');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export interface NewTransaction {
	account_id: string;
	type: TxnType;
	amount_paise: number;
	category_id?: string | null;
	transfer_account_id?: string | null;
	note?: string | null;
	occurred_on?: string;
	recurring_id?: string | null;
}

export async function forAccountTxns(accountId: string): Promise<Transaction[]> {
	const { data, error } = await db()
		.from('transactions')
		.select('*')
		.or(`account_id.eq.${accountId},transfer_account_id.eq.${accountId}`);
	if (error) throw error;
	return (data ?? []) as Transaction[];
}

export async function listByMonth(monthKey: string): Promise<Transaction[]> {
	const [year, month] = monthKey.split('-').map(Number);
	const { start, end } = monthRange(year, month);
	const { data, error } = await db()
		.from('transactions')
		.select('*')
		.gte('occurred_on', start)
		.lte('occurred_on', end)
		.order('occurred_on', { ascending: false });
	if (error) throw error;
	return (data ?? []) as Transaction[];
}

// Import accountsRepo lazily-at-call-time to avoid top-level circular init.
async function applyToBalances(t: Transaction, sign: 1 | -1): Promise<void> {
	const { accountsRepo } = await import('./accounts');
	const ids = [t.account_id, t.transfer_account_id].filter(Boolean) as string[];
	for (const id of ids) {
		const acc = await accountsRepo.get(id);
		if (!acc) continue;
		const delta = balanceDelta(t, id) * sign;
		await accountsRepo.update(id, { balance_paise: acc.balance_paise + delta } as Partial<Account>);
	}
}

export async function createTransaction(input: NewTransaction): Promise<Transaction> {
	const row = {
		id: crypto.randomUUID(),
		account_id: input.account_id,
		category_id: input.category_id ?? null,
		type: input.type,
		amount_paise: input.amount_paise,
		transfer_account_id: input.transfer_account_id ?? null,
		note: input.note ?? null,
		occurred_on: input.occurred_on ?? todayIso(),
		recurring_id: input.recurring_id ?? null
	};
	if (navigator.onLine) {
		const created = await txnRepo.create(row as Partial<Transaction>);
		await applyToBalances(created, 1);
		return created;
	}
	// Offline: queue the insert; reconcileAll() on next online open repairs balances.
	await enqueue({ table: 'transactions', op: 'create', payload: { data: row }, createdAt: Date.now() });
	return row as Transaction;
}

export async function updateTransaction(prev: Transaction, patch: Partial<Transaction>): Promise<Transaction> {
	const next = { ...prev, ...patch };
	if (navigator.onLine) {
		await applyToBalances(prev, -1);
		const updated = await txnRepo.update(prev.id, patch);
		await applyToBalances(updated, 1);
		return updated;
	}
	await enqueue({ table: 'transactions', op: 'update', payload: { id: prev.id, data: patch as Record<string, unknown> }, createdAt: Date.now() });
	return next;
}

export async function deleteTransaction(t: Transaction): Promise<void> {
	if (navigator.onLine) {
		await applyToBalances(t, -1);
		await txnRepo.remove(t.id);
		return;
	}
	await enqueue({ table: 'transactions', op: 'remove', payload: { id: t.id }, createdAt: Date.now() });
}
