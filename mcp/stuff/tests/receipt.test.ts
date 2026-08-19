import { describe, expect, test } from 'bun:test';
import { asinFrom, canonicalLink, parseDate, parseInr } from '../src/receipt';

describe('product links', () => {
	test('an Amazon link reduces to its ASIN', () => {
		expect(
			canonicalLink(
				'https://www.amazon.in/CMF-Nothing-Cancellation-Playtime-Bluetooth/dp/B0D9G1YQPZ/ref=sr_1_3?crid=X&qid=1755&sr=8-3&th=1'
			)
		).toBe('https://www.amazon.in/dp/B0D9G1YQPZ');
	});

	test('two links to the same product become the same string', () => {
		const a = canonicalLink('https://www.amazon.in/dp/B0D9G1YQPZ?tag=someone-21');
		const b = canonicalLink('https://www.amazon.in/gp/product/B0D9G1YQPZ/ref=ppx_yo_dt_b_asin_title');
		expect(a).toBe(b);
	});

	test('non-Amazon links keep their path and lose only the tracking', () => {
		expect(canonicalLink('https://shop.example.com/things/kettle?utm_source=mail&size=1L')).toBe(
			'https://shop.example.com/things/kettle?size=1L'
		);
	});

	test('something that is not a URL survives untouched', () => {
		expect(canonicalLink('bought at the shop downstairs')).toBe('bought at the shop downstairs');
		expect(canonicalLink('')).toBe('');
	});

	test('ASIN extraction', () => {
		expect(asinFrom('/dp/B0D9G1YQPZ')).toBe('B0D9G1YQPZ');
		expect(asinFrom('/gp/aw/d/B0D9G1YQPZ/')).toBe('B0D9G1YQPZ');
		expect(asinFrom('/some/other/path')).toBeNull();
	});
});

describe('prices as receipts write them', () => {
	test('rupee symbol, grouping and paise', () => {
		expect(parseInr('₹2,499.00')).toBe(2499);
		expect(parseInr('Rs. 1,09,999')).toBe(109999);
		expect(parseInr('2499')).toBe(2499);
		expect(parseInr(2499)).toBe(2499);
		expect(parseInr('INR 799.50')).toBe(799);
	});

	test('nothing usable is null, not zero — the caller decides what that means', () => {
		expect(parseInr('')).toBeNull();
		expect(parseInr(null)).toBeNull();
		expect(parseInr('free')).toBeNull();
	});
});

describe('dates as receipts write them', () => {
	test('the shapes an order page uses', () => {
		expect(parseDate('2026-08-19')).toBe('2026-08-19');
		expect(parseDate('19 August 2026')).toBe('2026-08-19');
		expect(parseDate('19th Aug, 2026')).toBe('2026-08-19');
		expect(parseDate('August 19, 2026')).toBe('2026-08-19');
		expect(parseDate('Ordered on 19 September 2026')).toBe('2026-09-19');
	});

	test('numeric dates are read day-first, the way Indian invoices write them', () => {
		expect(parseDate('08/09/2026')).toBe('2026-09-08');
		expect(parseDate('19-08-26')).toBe('2026-08-19');
	});

	test('a nonsense date is null so the caller can fall back to today', () => {
		expect(parseDate('sometime last week')).toBeNull();
		expect(parseDate('')).toBeNull();
		expect(parseDate('45/45/2026')).toBeNull();
	});
});
