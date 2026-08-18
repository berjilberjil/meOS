import { describe, it, expect } from 'vitest';
import { kgToG, gToKg, kmToM, mToKm, hoursToMin, minToHours } from '$lib/health/units';
import { totalDuration } from '$lib/health/logs';
import type { FitnessLog } from '$lib/health/types';

describe('unit conversions', () => {
	it('weight kg<->g (integer grams)', () => {
		expect(kgToG(72.5)).toBe(72500);
		expect(gToKg(72500)).toBe(72.5);
	});
	it('distance km<->m', () => {
		expect(kmToM(5.2)).toBe(5200);
		expect(mToKm(5200)).toBe(5.2);
	});
	it('time hours<->min', () => {
		expect(hoursToMin(7.5)).toBe(450);
		expect(minToHours(450)).toBe(7.5);
	});
});

function fit(p: Partial<FitnessLog>): FitnessLog {
	return {
		id: 'f', user_id: 'u', logged_on: '2026-06-26', activity: 'run', duration_min: 0,
		calories: null, distance_m: null, notes: null, created_at: '', updated_at: '', ...p
	};
}

describe('totalDuration', () => {
	it('sums workout minutes within the trailing window', () => {
		const logs = [
			fit({ logged_on: '2026-06-26', duration_min: 30 }),
			fit({ logged_on: '2026-06-20', duration_min: 45 }), // within 7 days of the 26th
			fit({ logged_on: '2026-06-10', duration_min: 60 }) // outside
		];
		expect(totalDuration(logs, '2026-06-26', 7)).toBe(75);
	});
});
