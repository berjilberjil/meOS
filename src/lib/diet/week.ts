function pad(n: number): string {
	return n < 10 ? `0${n}` : `${n}`;
}

function fmt(d: Date): string {
	return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

function parse(iso: string): Date {
	const [y, m, day] = iso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, day));
}

/** Monday of the ISO week containing `iso` (YYYY-MM-DD). */
export function weekStartMonday(iso: string): string {
	const d = parse(iso);
	const day = d.getUTCDay(); // 0=Sun … 6=Sat
	const offset = day === 0 ? -6 : 1 - day;
	d.setUTCDate(d.getUTCDate() + offset);
	return fmt(d);
}

export function shiftWeek(weekStart: string, weeks: number): string {
	const d = parse(weekStartMonday(weekStart));
	d.setUTCDate(d.getUTCDate() + weeks * 7);
	return fmt(d);
}

/** 0=Mon … 6=Sun */
export function weekdayIndex(iso: string): number {
	const day = parse(iso).getUTCDay();
	return day === 0 ? 6 : day - 1;
}

export const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const;

export function dateForWeekday(weekStart: string, weekday: number): string {
	const d = parse(weekStartMonday(weekStart));
	d.setUTCDate(d.getUTCDate() + weekday);
	return fmt(d);
}
