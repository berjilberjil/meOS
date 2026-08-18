import { describe, it, expect } from 'vitest';
import { toPaise, fromPaise, formatINR, sumPaise } from '$lib/money';

describe('money', () => {
	it('converts rupees to integer paise without float drift', () => {
		expect(toPaise(19.99)).toBe(1999);
		expect(toPaise(0.1)).toBe(10);
		expect(toPaise(40000)).toBe(4000000);
	});
	it('round-trips', () => {
		expect(fromPaise(toPaise(1234.56))).toBe(1234.56);
	});
	it('formats INR', () => {
		expect(formatINR(4000000)).toContain('40,000');
		expect(formatINR(4000000)).toContain('₹');
	});
	it('sums paise with no float drift', () => {
		expect(sumPaise([1999, 1, 4000000])).toBe(4002000);
		expect(sumPaise([])).toBe(0);
	});
});
