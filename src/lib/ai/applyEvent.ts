import { addTodo } from '$lib/planner/todos';
import { createNote } from '$lib/notes/notes';
import { createEntry } from '$lib/journal/entries';
import { addFitness } from '$lib/health/logs';
import { accountsRepo } from '$lib/finance/accounts';
import { categoriesRepo } from '$lib/finance/categories';
import { createTransaction } from '$lib/finance/transactions';
import type { JournalDoc } from '$lib/journal/types';
import type { Priority } from '$lib/planner/types';
import type { CategorizedEvent } from './categorize';

function paraDoc(text: string): JournalDoc {
	return {
		type: 'doc',
		content: text
			? [{ type: 'paragraph', content: [{ type: 'text', text }] }]
			: [{ type: 'paragraph' }]
	};
}

export interface AppliedEvent {
	message: string;
	href: string;
}

export async function applyCategorizedEvent(ev: CategorizedEvent): Promise<AppliedEvent> {
	if (ev.kind === 'finance' && ev.amount_paise && ev.amount_paise > 0) {
		const accounts = (await accountsRepo.list()).filter((a) => !a.archived);
		const account = accounts[0];
		if (account) {
			const cats = await categoriesRepo.list();
			const cat = ev.category
				? cats.find((c) => c.name.toLowerCase() === ev.category!.toLowerCase())
				: null;
			const income =
				cat?.kind === 'income' ||
				/\b(salary|earned|income|paid me|received)\b/i.test(ev.title);
			await createTransaction({
				account_id: account.id,
				type: income ? 'income' : 'expense',
				amount_paise: ev.amount_paise,
				category_id: cat?.id ?? null,
				note: ev.title,
				occurred_on: ev.date
			});
			return { message: `Logged ${ev.title}`, href: '/finance/transactions' };
		}
	}

	if (ev.kind === 'journal') {
		await createEntry({
			title: ev.title,
			body_json: paraDoc(ev.notes ?? ev.title),
			occurred_on: ev.date
		});
		return { message: 'Journal note saved', href: '/journal' };
	}

	if (ev.kind === 'note') {
		await createNote({
			title: ev.title,
			body_json: paraDoc(ev.notes ?? ev.title),
			pinned: false
		});
		return { message: `Saved note: ${ev.title}`, href: '/notes' };
	}

	if (ev.kind === 'fitness') {
		const mins = ev.notes?.match(/(\d+)\s*(min|mins|minutes)?/i);
		await addFitness({
			logged_on: ev.date,
			activity: ev.title,
			duration_min: mins ? Number(mins[1]) : 0,
			distance_m: null,
			calories: null
		});
		return { message: `Logged ${ev.title}`, href: '/fitness/workouts' };
	}

	await addTodo(ev.title, ev.date, ev.priority as Priority);
	return { message: `Added “${ev.title}”`, href: '/todos' };
}
