import { describe, it, expect } from 'vitest';
import { ringFraction, donutDashArray } from '$lib/components/charts/ring';

describe('ringFraction', () => {
	it('clamps to 0..1', () => {
		expect(ringFraction(50, 100)).toBe(0.5);
		expect(ringFraction(150, 100)).toBe(1);
		expect(ringFraction(10, 0)).toBe(0);
		expect(ringFraction(-5, 100)).toBe(0);
	});
});

describe('donutDashArray', () => {
	it('produces a dash segment per value, offsets accumulating', () => {
		const segs = donutDashArray([25, 75], 100);
		expect(segs[0]).toEqual({ dash: 25, gap: 75, offset: 0 });
		expect(segs[1]).toEqual({ dash: 75, gap: 25, offset: -25 });
	});
	it('handles all-zero safely', () => {
		expect(donutDashArray([0, 0], 100)).toEqual([
			{ dash: 0, gap: 100, offset: 0 },
			{ dash: 0, gap: 100, offset: 0 }
		]);
	});
});
