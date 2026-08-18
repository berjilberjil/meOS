import { describe, it, expect } from 'vitest';
import {
	parseCategorizedEvent,
	resolveRelativeDate,
	extractJson
} from '$lib/ai/categorize';

describe('extractJson', () => {
	it('parses a raw object and a fenced blob', () => {
		expect(extractJson('{"a":1}')).toEqual({ a: 1 });
		expect(extractJson('Sure.\n```json\n{"a":2}\n```')).toEqual({ a: 2 });
	});

	it('returns null when nothing looks like JSON', () => {
		expect(extractJson('nope')).toBeNull();
	});
});

describe('resolveRelativeDate', () => {
	const today = '2026-08-15';
	it('resolves today, tomorrow, and an explicit ISO date', () => {
		expect(resolveRelativeDate('do it today please', today)).toBe('2026-08-15');
		expect(resolveRelativeDate('dentist tomorrow', today)).toBe('2026-08-16');
		expect(resolveRelativeDate('flight on 2026-09-02', today)).toBe('2026-09-02');
	});
	it('falls back to today when no date is mentioned', () => {
		expect(resolveRelativeDate('buy milk', today)).toBe(today);
	});
});

describe('parseCategorizedEvent', () => {
	const today = '2026-08-15';

	it('accepts a well-formed AI payload', () => {
		const ev = parseCategorizedEvent(
			{
				kind: 'finance',
				title: 'Groceries at Nature\'s Basket',
				date: '2026-08-16',
				category: 'Groceries',
				amount_paise: 45000,
				priority: 2,
				notes: 'milk + eggs'
			},
			today
		);
		expect(ev).toEqual({
			kind: 'finance',
			title: 'Groceries at Nature\'s Basket',
			date: '2026-08-16',
			category: 'Groceries',
			amount_paise: 45000,
			priority: 2,
			notes: 'milk + eggs'
		});
	});

	it('falls back to a todo on today when the model returns garbage', () => {
		const ev = parseCategorizedEvent('???', today);
		expect(ev.kind).toBe('todo');
		expect(ev.date).toBe(today);
		expect(ev.title.length).toBeGreaterThan(0);
	});

	it('clamps unknown kinds and bad priority, and fills a missing date', () => {
		const ev = parseCategorizedEvent(
			{ kind: 'spaceship', title: 'Launch', priority: 99, date: '' },
			today
		);
		expect(ev.kind).toBe('todo');
		expect(ev.priority).toBe(0);
		expect(ev.date).toBe(today);
		expect(ev.title).toBe('Launch');
	});

	it('uses the spoken text as the title when the model omits one', () => {
		const ev = parseCategorizedEvent({ kind: 'todo' }, today, 'Call the plumber tomorrow');
		expect(ev.title).toBe('Call the plumber tomorrow');
	});
});
