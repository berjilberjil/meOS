import { describe, it, expect, beforeEach, vi } from 'vitest';
import { applyTheme, setTheme, getStoredTheme } from '$lib/stores/theme.svelte';

beforeEach(() => {
	localStorage.clear();
	document.documentElement.className = '';
	vi.restoreAllMocks();
});

describe('theme store', () => {
	it('applies dark class for dark theme', () => {
		applyTheme('dark');
		expect(document.documentElement.classList.contains('dark')).toBe(true);
		expect(document.documentElement.classList.contains('tui')).toBe(false);
	});

	it('light theme clears dark', () => {
		applyTheme('dark');
		applyTheme('light');
		expect(document.documentElement.classList.contains('dark')).toBe(false);
		expect(document.documentElement.classList.contains('tui')).toBe(false);
	});

	it('setTheme persists to localStorage', () => {
		setTheme('dark');
		expect(localStorage.getItem('theme')).toBe('dark');
		expect(getStoredTheme()).toBe('dark');
	});

	it('migrates legacy tui to dark', () => {
		localStorage.setItem('theme', 'tui');
		expect(getStoredTheme()).toBe('dark');
	});

	it('getStoredTheme defaults to system', () => {
		expect(getStoredTheme()).toBe('system');
	});
});
