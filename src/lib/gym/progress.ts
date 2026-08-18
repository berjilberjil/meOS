// Pure gym-progress math, derived from raw session sets. Never stored.
import { addDaysIso } from '$lib/streak/streak';
import type { SessionSet } from './types';

/** Epley estimated 1-rep-max, in grams. At reps=1 it equals the weight. */
export function epley1RM(weightG: number, reps: number): number {
	if (reps <= 0 || weightG <= 0) return 0;
	if (reps === 1) return weightG; // a single rep IS your 1RM
	return Math.round(weightG * (1 + reps / 30));
}

export function best1RM(sets: SessionSet[]): number {
	return sets.reduce((m, s) => Math.max(m, epley1RM(s.weight_g, s.reps)), 0);
}

export function bestWeight(sets: SessionSet[]): number {
	return sets.reduce((m, s) => Math.max(m, s.weight_g), 0);
}

/** Total tonnage = Σ weight × reps. */
export function sessionVolume(sets: SessionSet[]): number {
	return sets.reduce((sum, s) => sum + s.weight_g * s.reps, 0);
}

/** Consecutive days (back from today) with ≥1 session. Today counts if trained. */
export function sessionStreak(dates: string[], todayIso: string): number {
	const set = new Set(dates);
	let cursor = todayIso;
	if (!set.has(cursor)) cursor = addDaysIso(cursor, -1); // rest day today is OK
	let streak = 0;
	while (set.has(cursor)) {
		streak++;
		cursor = addDaysIso(cursor, -1);
	}
	return streak;
}

/** Distinct (day, muscle) pairs trained in the trailing 7 days, per muscle. */
export function muscleFrequency(
	items: { logged_on: string; muscle_group: string }[],
	todayIso: string
): Record<string, number> {
	const since = addDaysIso(todayIso, -6);
	const seen = new Set<string>();
	const counts: Record<string, number> = {};
	for (const it of items) {
		if (it.logged_on < since || it.logged_on > todayIso) continue;
		const k = `${it.logged_on}|${it.muscle_group}`;
		if (seen.has(k)) continue;
		seen.add(k);
		counts[it.muscle_group] = (counts[it.muscle_group] ?? 0) + 1;
	}
	return counts;
}

/** Per-day volume + best est-1RM for one exercise, oldest first (chart data). */
export function volumeSeries(
	sets: (SessionSet & { logged_on: string })[],
	exerciseId: string
): { date: string; volume: number; best1RM: number }[] {
	const byDate = new Map<string, SessionSet[]>();
	for (const s of sets) {
		if (s.exercise_id !== exerciseId) continue;
		const arr = byDate.get(s.logged_on) ?? [];
		arr.push(s);
		byDate.set(s.logged_on, arr);
	}
	return [...byDate.entries()]
		.map(([date, ss]) => ({ date, volume: sessionVolume(ss), best1RM: best1RM(ss) }))
		.sort((a, b) => a.date.localeCompare(b.date));
}
