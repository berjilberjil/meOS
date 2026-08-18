import { describe, it, expect } from 'vitest';
import {
	addDaysIso,
	computeStreak,
	monthDayStates,
	daysPracticed,
	lastSevenDays
} from '../../src/lib/streak/streak';

const set = (...d: string[]) => new Set(d);

describe('addDaysIso', () => {
	it('adds and subtracts across month boundaries', () => {
		expect(addDaysIso('2026-06-27', 1)).toBe('2026-06-28');
		expect(addDaysIso('2026-06-01', -1)).toBe('2026-05-31');
		expect(addDaysIso('2026-03-01', -1)).toBe('2026-02-28');
	});
});

describe('computeStreak', () => {
	it('counts consecutive logged days ending today', () => {
		const r = computeStreak(set('2026-06-25', '2026-06-26', '2026-06-27'), '2026-06-27', 3);
		expect(r.current).toBe(3);
		expect(r.todayDone).toBe(true);
		expect(r.freezesUsed).toBe(0);
	});

	it('holds the streak through yesterday when today is not done yet', () => {
		const r = computeStreak(set('2026-06-25', '2026-06-26'), '2026-06-27', 3);
		expect(r.current).toBe(2);
		expect(r.todayDone).toBe(false);
	});

	it('covers a missed day with a freeze and keeps going', () => {
		// missed the 26th, logged 24,25,27
		const r = computeStreak(set('2026-06-24', '2026-06-25', '2026-06-27'), '2026-06-27', 3);
		expect(r.current).toBe(4); // 27,26(frozen),25,24
		expect(r.freezesUsed).toBe(1);
		expect(r.frozen.has('2026-06-26')).toBe(true);
	});

	it('breaks when freezes run out', () => {
		// today logged, then two missed days, no freezes
		const r = computeStreak(set('2026-06-27', '2026-06-24'), '2026-06-27', 0);
		expect(r.current).toBe(1); // only today; 26 missed, no freeze -> stop
		expect(r.freezesUsed).toBe(0);
	});

	it('is zero when nothing logged recently', () => {
		const r = computeStreak(set('2026-01-01'), '2026-06-27', 3);
		expect(r.current).toBe(0);
	});
});

describe('monthDayStates', () => {
	it('classifies future, today, logged, frozen and missed', () => {
		const logged = set('2026-06-01', '2026-06-27');
		const frozen = set('2026-06-10');
		const states = monthDayStates(2026, 6, logged, frozen, '2026-06-27');
		expect(states.get('2026-06-01')).toBe('logged');
		expect(states.get('2026-06-10')).toBe('frozen');
		expect(states.get('2026-06-05')).toBe('missed');
		expect(states.get('2026-06-27')).toBe('logged');
		expect(states.get('2026-06-28')).toBe('future');
	});

	it('marks an un-logged today as today', () => {
		const states = monthDayStates(2026, 6, set(), set(), '2026-06-27');
		expect(states.get('2026-06-27')).toBe('today');
	});
});

describe('daysPracticed', () => {
	it('counts logged days within the month only', () => {
		const logged = set('2026-06-01', '2026-06-02', '2026-05-31');
		expect(daysPracticed(2026, 6, logged)).toBe(2);
	});
});

describe('lastSevenDays', () => {
	it('returns 7 days oldest-first ending today', () => {
		const week = lastSevenDays(set('2026-06-27', '2026-06-26'), '2026-06-27');
		expect(week).toHaveLength(7);
		expect(week[6]).toEqual({ iso: '2026-06-27', done: true, isToday: true });
		expect(week[5].done).toBe(true);
		expect(week[0].done).toBe(false);
	});
});
