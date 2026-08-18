import { describe, it, expect } from 'vitest';
import { pendingDates } from '$lib/finance/recurring';

describe('pendingDates', () => {
	it('drops dates already posted for this recurring item', () => {
		expect(pendingDates(['2026-04-15', '2026-05-15', '2026-06-15'], ['2026-04-15'])).toEqual([
			'2026-05-15',
			'2026-06-15'
		]);
	});
	it('returns all when nothing posted', () => {
		expect(pendingDates(['2026-06-15'], [])).toEqual(['2026-06-15']);
	});
	it('returns none when all posted', () => {
		expect(pendingDates(['2026-06-15'], ['2026-06-15'])).toEqual([]);
	});
});
