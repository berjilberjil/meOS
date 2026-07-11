import { describe, it, expect } from 'vitest';
import {
	epley1RM,
	best1RM,
	bestWeight,
	sessionVolume,
	sessionStreak,
	muscleFrequency,
	volumeSeries
} from '$lib/gym/progress';
import type { SessionSet } from '$lib/gym/types';

function set(p: Partial<SessionSet>): SessionSet {
	return {
		id: 's', user_id: 'u', session_id: 'sess', exercise_id: 'bench', set_number: 1,
		reps: 5, weight_g: 60000, rpe: null, created_at: '', ...p
	};
}

describe('epley1RM', () => {
	it('equals the weight at a single rep', () => {
		expect(epley1RM(100000, 1)).toBe(100000);
	});
	it('estimates above the weight for multiple reps', () => {
		expect(epley1RM(100000, 10)).toBe(133333); // 100000 * (1 + 10/30)
	});
	it('is zero for no reps or no weight', () => {
		expect(epley1RM(100000, 0)).toBe(0);
		expect(epley1RM(0, 5)).toBe(0);
	});
});

describe('set aggregates', () => {
	const sets = [
		set({ weight_g: 60000, reps: 5 }),
		set({ weight_g: 65000, reps: 3 }),
		set({ weight_g: 70000, reps: 1 })
	];
	it('bestWeight is the heaviest single', () => {
		expect(bestWeight(sets)).toBe(70000);
	});
	it('best1RM is the best estimate across sets', () => {
		// 60000*(1+5/30)=70000 ; 65000*(1+3/30)=71500 ; 70000@1=70000 → 71500
		expect(best1RM(sets)).toBe(71500);
	});
	it('sessionVolume sums weight × reps', () => {
		expect(sessionVolume(sets)).toBe(60000 * 5 + 65000 * 3 + 70000 * 1);
	});
});

describe('sessionStreak', () => {
	it('counts consecutive days back from today', () => {
		expect(sessionStreak(['2026-07-11', '2026-07-10', '2026-07-09'], '2026-07-11')).toBe(3);
	});
	it('still counts if today is a rest day but yesterday trained', () => {
		expect(sessionStreak(['2026-07-10', '2026-07-09'], '2026-07-11')).toBe(2);
	});
	it('breaks on a gap', () => {
		expect(sessionStreak(['2026-07-11', '2026-07-08'], '2026-07-11')).toBe(1);
	});
	it('is zero with no recent sessions', () => {
		expect(sessionStreak(['2026-07-01'], '2026-07-11')).toBe(0);
	});
});

describe('muscleFrequency', () => {
	it('counts distinct day+muscle pairs in the last 7 days', () => {
		const items = [
			{ logged_on: '2026-07-11', muscle_group: 'chest' },
			{ logged_on: '2026-07-11', muscle_group: 'chest' }, // same day+muscle → 1
			{ logged_on: '2026-07-09', muscle_group: 'chest' },
			{ logged_on: '2026-07-10', muscle_group: 'legs' },
			{ logged_on: '2026-07-01', muscle_group: 'back' } // outside 7d window
		];
		expect(muscleFrequency(items, '2026-07-11')).toEqual({ chest: 2, legs: 1 });
	});
});

describe('volumeSeries', () => {
	it('groups one exercise by day, oldest first', () => {
		const sets = [
			{ ...set({ weight_g: 60000, reps: 5 }), logged_on: '2026-07-10' },
			{ ...set({ weight_g: 62000, reps: 5 }), logged_on: '2026-07-11' },
			{ ...set({ exercise_id: 'squat', weight_g: 100000, reps: 5 }), logged_on: '2026-07-11' }
		];
		const s = volumeSeries(sets, 'bench');
		expect(s.map((p) => p.date)).toEqual(['2026-07-10', '2026-07-11']);
		expect(s[0].volume).toBe(300000);
	});
});
