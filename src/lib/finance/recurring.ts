import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import { catchUpOccurrences } from './calc';
import { todayIso } from './dates';
import { createTransaction } from './transactions';
import type { Recurring, TxnType } from './types';

export const recurringRepo = new SupabaseRepository<Recurring>('recurring');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export function pendingDates(dates: string[], existing: string[]): string[] {
	const seen = new Set(existing);
	return dates.filter((d) => !seen.has(d));
}

async function existingDatesFor(recurringId: string): Promise<string[]> {
	const { data, error } = await db().from('transactions').select('occurred_on').eq('recurring_id', recurringId);
	if (error) throw error;
	return (data ?? []).map((r: { occurred_on: string }) => r.occurred_on);
}

export async function listActiveSorted(): Promise<Recurring[]> {
	const items = await recurringRepo.list();
	return items.filter((r) => r.active).sort((a, b) => a.next_run_on.localeCompare(b.next_run_on));
}

export async function runCatchUp(today: string = todayIso()): Promise<number> {
	const items = await recurringRepo.list();
	let posted = 0;
	for (const r of items) {
		if (!r.active) continue;
		const { dates, nextRunOn } = catchUpOccurrences(r.next_run_on, r.cadence, r.interval_days, today);
		if (!dates.length) continue;
		const existing = await existingDatesFor(r.id);
		const toPost = pendingDates(dates, existing);
		const txnType: TxnType = r.kind === 'income' ? 'income' : 'expense';
		for (const d of toPost) {
			await createTransaction({
				account_id: r.account_id,
				type: txnType,
				amount_paise: r.amount_paise,
				category_id: r.category_id,
				note: r.name,
				occurred_on: d,
				recurring_id: r.id
			});
			if (r.investment_id) {
				const { investmentsRepo } = await import('./investments');
				const inv = await investmentsRepo.get(r.investment_id);
				if (inv) await investmentsRepo.update(r.investment_id, { invested_paise: inv.invested_paise + r.amount_paise });
			}
			posted++;
		}
		await recurringRepo.update(r.id, { next_run_on: nextRunOn });
	}
	return posted;
}
