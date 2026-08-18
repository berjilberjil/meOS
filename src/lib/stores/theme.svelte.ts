export type Theme = 'light' | 'dark' | 'system';

const STORAGE_KEY = 'theme';

function prefersDark(): boolean {
	return (
		typeof window !== 'undefined' &&
		!!window.matchMedia?.('(prefers-color-scheme: dark)').matches
	);
}

export function getStoredTheme(): Theme {
	if (typeof localStorage === 'undefined') return 'system';
	const v = localStorage.getItem(STORAGE_KEY);
	// 'tui' (Tokyo Night) was removed — fall back to dark.
	if (v === 'tui') return 'dark';
	return (v as Theme) ?? 'system';
}

export function applyTheme(theme: Theme): void {
	const root = document.documentElement;
	const dark = theme === 'dark' || (theme === 'system' && prefersDark());
	root.classList.remove('tui');
	root.classList.toggle('dark', dark);
}

export function setTheme(theme: Theme): void {
	localStorage.setItem(STORAGE_KEY, theme);
	applyTheme(theme);
}

export const themeState = $state<{ current: Theme }>({ current: 'system' });

export function initTheme(): void {
	themeState.current = getStoredTheme();
	applyTheme(themeState.current);
}
