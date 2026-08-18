import { describe, it, expect } from 'vitest';
import { parseScanResult } from '$lib/ai/scan';

describe('parseScanResult', () => {
	it('reads a food payload and keeps macros as grams', () => {
		const r = parseScanResult({
			kind: 'food',
			name: 'Masala dosa',
			serving: '1 plate',
			energy_kcal: 350,
			protein_g: 8,
			carb_g: 52,
			fat_g: 10,
			detail: 'Fermented rice-lentil crepe with potato filling.'
		});
		expect(r).toEqual({
			kind: 'food',
			name: 'Masala dosa',
			serving: '1 plate',
			energy_kcal: 350,
			protein_g: 8,
			carb_g: 52,
			fat_g: 10,
			detail: 'Fermented rice-lentil crepe with potato filling.'
		});
	});

	it('reads an object payload with a needed verdict', () => {
		const r = parseScanResult({
			kind: 'object',
			name: 'Adjustable dumbbell',
			needed: 'yes',
			why: 'You already train; this covers more loads at home.',
			useful: 'Replaces a rack of plates if space is tight.'
		});
		expect(r.kind).toBe('object');
		if (r.kind === 'object') {
			expect(r.needed).toBe('yes');
			expect(r.name).toBe('Adjustable dumbbell');
		}
	});

	it('treats unknown or empty payloads as an unidentified object', () => {
		const r = parseScanResult(null);
		expect(r.kind).toBe('object');
		if (r.kind === 'object') {
			expect(r.needed).toBe('maybe');
			expect(r.name.length).toBeGreaterThan(0);
		}
	});

	it('coerces a bad needed value and a missing food name', () => {
		const food = parseScanResult({ kind: 'food', energy_kcal: '120' });
		expect(food.kind).toBe('food');
		if (food.kind === 'food') {
			expect(food.name).toBe('Food');
			expect(food.energy_kcal).toBe(120);
		}
		const obj = parseScanResult({ kind: 'object', name: 'Thing', needed: 'absolutely' });
		expect(obj.kind).toBe('object');
		if (obj.kind === 'object') expect(obj.needed).toBe('maybe');
	});
});
