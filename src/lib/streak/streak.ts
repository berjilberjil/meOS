// Pure streak logic over a set of logged ISO dates (YYYY-MM-DD). No Date.now
// here — `today` is always passed in, so it stays deterministic and testable.

export type DayState = 'logged' | 'frozen' | 'missed' | 'today' | 'future';

export interface StreakResult {
	current: number; // streak length in days (includes freeze-covered days)
	freezesUsed: number; // missed days inside the run covered by a freeze
	frozen: Set<string>; // those covered dates
	todayDone: boolean;
}

// Shift a YYYY-MM-DD date by n days using UTC math (timezone-safe).
export function addDaysIso(iso: string, n: number): string {
	const [y, m, d] = iso.split('-').map(Number);
	const dt = new Date(Date.UTC(y, m - 1, d));
	dt.setUTCDate(dt.getUTCDate() + n);
	return dt.toISOString().slice(0, 10);
}

// Local calendar day as YYYY-MM-DD (avoids the UTC off-by-one of toISOString).
export function localToday(d: Date): string {
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

export function computeStreak(
	logged: Set<string>,
	today: string,
	freezesTotal: number
): StreakResult {
	const todayDone = logged.has(today);
	let cursor = todayDone ? today : addDaysIso(today, -1);
	const run: { iso: string; frozen: boolean }[] = [];
	let usedFreezes = 0;

	// Walk backwards collecting a covered run: logged days, plus gaps bridged by
	// a freeze while the budget lasts. Stop at an uncoverable gap.
	for (let guard = 0; guard < 4000; guard++) {
		if (logged.has(cursor)) {
			run.push({ iso: cursor, frozen: false });
		} else if (usedFreezes < freezesTotal) {
			usedFreezes++;
			run.push({ iso: cursor, frozen: true });
		} else {
			break;
		}
		cursor = addDaysIso(cursor, -1);
	}

	// Trim trailing (oldest) freeze-covered days that aren't anchored by a logged
	// day — a streak built only from freezes isn't a streak.
	while (run.length && run[run.length - 1].frozen) run.pop();

	const frozen = new Set(run.filter((r) => r.frozen).map((r) => r.iso));
	return { current: run.length, freezesUsed: frozen.size, frozen, todayDone };
}

// State for every day of a month grid, for the calendar.
export function monthDayStates(
	year: number,
	month1: number, // 1-12
	logged: Set<string>,
	frozen: Set<string>,
	today: string
): Map<string, DayState> {
	const out = new Map<string, DayState>();
	const days = new Date(Date.UTC(year, month1, 0)).getUTCDate(); // last day of month
	for (let d = 1; d <= days; d++) {
		const iso = `${year}-${String(month1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
		let state: DayState;
		if (iso > today) state = 'future';
		else if (iso === today) state = logged.has(iso) ? 'logged' : 'today';
		else if (logged.has(iso)) state = 'logged';
		else if (frozen.has(iso)) state = 'frozen';
		else state = 'missed';
		out.set(iso, state);
	}
	return out;
}

// Count of practiced (logged) days within a month.
export function daysPracticed(year: number, month1: number, logged: Set<string>): number {
	const prefix = `${year}-${String(month1).padStart(2, '0')}-`;
	let n = 0;
	for (const iso of logged) if (iso.startsWith(prefix)) n++;
	return n;
}

// Last 7 calendar days ending today, with whether each was logged — for the
// "this week" row. Returns oldest-first.
export function lastSevenDays(
	logged: Set<string>,
	today: string
): { iso: string; done: boolean; isToday: boolean }[] {
	const out: { iso: string; done: boolean; isToday: boolean }[] = [];
	for (let i = 6; i >= 0; i--) {
		const iso = addDaysIso(today, -i);
		out.push({ iso, done: logged.has(iso), isToday: iso === today });
	}
	return out;
}
