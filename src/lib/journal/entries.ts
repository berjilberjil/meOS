import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import { monthRange, todayIso } from '$lib/finance/dates';
import { extractText } from './text';
import type { JournalDoc, JournalEntry } from './types';

export const entriesRepo = new SupabaseRepository<JournalEntry>('journal_entries');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export interface NewEntry {
	id?: string;
	title?: string;
	body_json: JournalDoc;
	mood?: string | null;
	occurred_on?: string;
}

export async function listByMonth(monthKey: string): Promise<JournalEntry[]> {
	const [year, month] = monthKey.split('-').map(Number);
	const { start, end } = monthRange(year, month);
	const { data, error } = await db()
		.from('journal_entries')
		.select('*')
		.gte('occurred_on', start)
		.lte('occurred_on', end)
		.order('occurred_on', { ascending: false });
	if (error) throw error;
	return (data ?? []) as JournalEntry[];
}

export async function createEntry(input: NewEntry): Promise<JournalEntry> {
	return entriesRepo.create({
		id: input.id ?? crypto.randomUUID(),
		title: input.title ?? '',
		body_json: input.body_json,
		body_text: extractText(input.body_json),
		mood: input.mood ?? null,
		occurred_on: input.occurred_on ?? todayIso()
	} as Partial<JournalEntry>);
}

export async function updateEntry(id: string, input: NewEntry): Promise<JournalEntry> {
	return entriesRepo.update(id, {
		title: input.title ?? '',
		body_json: input.body_json,
		body_text: extractText(input.body_json),
		mood: input.mood ?? null,
		occurred_on: input.occurred_on
	} as Partial<JournalEntry>);
}
