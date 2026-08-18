import { supabaseBrowser } from '$lib/supabase/client';
import { addDaysIso } from './streak';

export interface StreakSettings {
	freezes_total: number;
	streak_goal: number;
}

const DEFAULTS: StreakSettings = { freezes_total: 3, streak_goal: 150 };

export async function getStreakSettings(): Promise<StreakSettings> {
	const { data } = await supabaseBrowser()
		.from('streak_settings')
		.select('freezes_total, streak_goal')
		.maybeSingle();
	return (data as StreakSettings | null) ?? DEFAULTS;
}

// All distinct dates with a journal entry, going back far enough for the
// streak run and a year of calendar.
export async function loggedJournalDates(today: string): Promise<Set<string>> {
	const since = addDaysIso(today, -400);
	const { data } = await supabaseBrowser()
		.from('journal_entries')
		.select('occurred_on')
		.gte('occurred_on', since);
	return new Set((data ?? []).map((r) => (r as { occurred_on: string }).occurred_on));
}

// The id of an entry on a given date, if one exists (for click-to-open).
export async function entryIdForDate(iso: string): Promise<string | null> {
	const { data } = await supabaseBrowser()
		.from('journal_entries')
		.select('id')
		.eq('occurred_on', iso)
		.order('updated_at', { ascending: false })
		.limit(1)
		.maybeSingle();
	return (data as { id: string } | null)?.id ?? null;
}
