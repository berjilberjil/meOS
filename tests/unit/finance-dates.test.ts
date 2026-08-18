import { describe, it, expect } from 'vitest';
import { monthKey, monthRange, advanceDate, nextMonthlyOn } from '$lib/finance/dates';

describe('finance dates', () => {
	it('monthKey extracts YYYY-MM', () => {
		expect(monthKey('2026-06-26')).toBe('2026-06');
	});
	it('monthRange returns first and last day', () => {
		expect(monthRange(2026, 2)).toEqual({ start: '2026-02-01', end: '2026-02-28' });
		expect(monthRange(2024, 2)).toEqual({ start: '2024-02-01', end: '2024-02-29' });
		expect(monthRange(2026, 6)).toEqual({ start: '2026-06-01', end: '2026-06-30' });
	});
	it('advanceDate monthly adds one month', () => {
		expect(advanceDate('2026-01-31', 'monthly', null)).toBe('2026-02-28');
		expect(advanceDate('2026-06-15', 'monthly', null)).toBe('2026-07-15');
	});
	it('advanceDate weekly adds 7 days', () => {
		expect(advanceDate('2026-06-26', 'weekly', null)).toBe('2026-07-03');
	});
	it('advanceDate custom adds intervalDays', () => {
		expect(advanceDate('2026-06-26', 'custom', 10)).toBe('2026-07-06');
	});
});

describe('nextMonthlyOn', () => {
	it('this month when the day has not passed', () => {
		expect(nextMonthlyOn(15, '2026-06-10')).toBe('2026-06-15');
	});
	it('today when the day is today', () => {
		expect(nextMonthlyOn(10, '2026-06-10')).toBe('2026-06-10');
	});
	it('next month when the day already passed', () => {
		expect(nextMonthlyOn(5, '2026-06-10')).toBe('2026-07-05');
	});
	it('clamps to the month length', () => {
		expect(nextMonthlyOn(31, '2026-02-01')).toBe('2026-02-28');
	});
});
