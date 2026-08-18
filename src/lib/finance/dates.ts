import type { Cadence } from './types';

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

export function todayIso(): string {
	return fmt(new Date());
}

export function monthKey(iso: string): string {
	return iso.slice(0, 7);
}

export function monthRange(year: number, month1: number): { start: string; end: string } {
	const start = new Date(Date.UTC(year, month1 - 1, 1));
	const end = new Date(Date.UTC(year, month1, 0)); // day 0 of next month = last day of this one
	return { start: fmt(start), end: fmt(end) };
}

export function advanceDate(iso: string, cadence: Cadence, intervalDays: number | null): string {
	const d = parse(iso);
	if (cadence === 'weekly') {
		d.setUTCDate(d.getUTCDate() + 7);
		return fmt(d);
	}
	if (cadence === 'custom') {
		d.setUTCDate(d.getUTCDate() + (intervalDays ?? 0));
		return fmt(d);
	}
	// monthly: clamp to the last valid day of the target month (e.g. Jan 31 -> Feb 28)
	const day = d.getUTCDate();
	const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1));
	const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
	target.setUTCDate(Math.min(day, lastDay));
	return fmt(target);
}

function clampDay(year: number, month1: number, day: number): string {
	const last = new Date(Date.UTC(year, month1, 0)).getUTCDate();
	return `${year}-${pad(month1)}-${pad(Math.min(day, last))}`;
}

export function nextMonthlyOn(day: number, today: string): string {
	const [y, m] = today.split('-').map(Number);
	const thisMonth = clampDay(y, m, day);
	if (thisMonth >= today) return thisMonth;
	const nm = new Date(Date.UTC(y, m, 1)); // m is 1-based, so this is the 1st of next month
	return clampDay(nm.getUTCFullYear(), nm.getUTCMonth() + 1, day);
}
