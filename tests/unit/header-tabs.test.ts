import { describe, it, expect, beforeEach } from 'vitest';
import { headerTabs, setHeaderTabs, clearHeaderTabs } from '$lib/stores/headerTabs.svelte';

const A = [{ href: '/finance', label: 'Overview' }];
const B = [{ href: '/fitness', label: 'Today' }];

beforeEach(() => {
	headerTabs.tabs = [];
});

describe('headerTabs ownership-based clearing', () => {
	it('setHeaderTabs publishes tabs and returns an owner token', () => {
		const token = setHeaderTabs(A);
		expect(headerTabs.tabs).toEqual(A);
		expect(typeof token).toBe('number');
	});

	it('an owner clears its own tabs', () => {
		const token = setHeaderTabs(A);
		clearHeaderTabs(token);
		expect(headerTabs.tabs).toEqual([]);
	});

	// The bug: navigating section A -> section B, B sets tabs, then A's onDestroy
	// fires clearHeaderTabs. It must NOT wipe B's tabs.
	it('a stale owner does not clear the newer owner tabs', () => {
		const tokenA = setHeaderTabs(A);
		setHeaderTabs(B); // section B took over
		clearHeaderTabs(tokenA); // section A unmounts afterwards
		expect(headerTabs.tabs).toEqual(B);
	});

	it('the current owner still clears', () => {
		setHeaderTabs(A);
		const tokenB = setHeaderTabs(B);
		clearHeaderTabs(tokenB);
		expect(headerTabs.tabs).toEqual([]);
	});
});
