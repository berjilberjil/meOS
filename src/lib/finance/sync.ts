import type { Repository } from '$lib/data/repository';
import { flush } from '$lib/data/sync-queue';
import { txnRepo } from './transactions';
import { accountsRepo, reconcileAll } from './accounts';
import { categoriesRepo } from './categories';
import { recurringRepo } from './recurring';
import { goalsRepo } from './goals';
import { investmentsRepo } from './investments';

export function resolveRepo(table: string): Repository<unknown> {
	switch (table) {
		case 'transactions': return txnRepo as Repository<unknown>;
		case 'accounts': return accountsRepo as Repository<unknown>;
		case 'categories': return categoriesRepo as Repository<unknown>;
		case 'recurring': return recurringRepo as Repository<unknown>;
		case 'savings_goals': return goalsRepo as Repository<unknown>;
		case 'investments': return investmentsRepo as Repository<unknown>;
		default: throw new Error(`No repo registered for table "${table}"`);
	}
}

export async function flushFinance(): Promise<number> {
	const n = await flush(resolveRepo);
	if (n > 0) await reconcileAll();
	return n;
}

export function initFinanceSync(onDone?: () => void): () => void {
	const run = () => {
		if (navigator.onLine) void flushFinance().then(() => onDone?.());
	};
	run();
	window.addEventListener('online', run);
	return () => window.removeEventListener('online', run);
}
