import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('$env/static/public', () => ({
	PUBLIC_SUPABASE_URL: 'https://example.supabase.co',
	PUBLIC_SUPABASE_ANON_KEY: 'anon'
}));

const createClient = vi.fn((..._args: unknown[]) => ({ id: 'mock-client' }));
vi.mock('@supabase/supabase-js', () => ({ createClient }));

beforeEach(() => {
	vi.resetModules();
	createClient.mockClear();
});

describe('supabaseBrowser', () => {
	it('returns the same instance twice (singleton)', async () => {
		const { supabaseBrowser } = await import('$lib/supabase/client');
		expect(supabaseBrowser()).toBe(supabaseBrowser());
	});

	it('persists the session in localStorage (not cookies) so it survives the tauri:// origin', async () => {
		const { supabaseBrowser } = await import('$lib/supabase/client');
		supabaseBrowser();
		expect(createClient).toHaveBeenCalledTimes(1);
		const opts = createClient.mock.calls[0][2] as {
			auth?: { persistSession?: boolean; autoRefreshToken?: boolean; storage?: unknown };
		};
		expect(opts.auth?.persistSession).toBe(true);
		expect(opts.auth?.autoRefreshToken).toBe(true);
		expect(opts.auth?.storage).toBe(globalThis.localStorage);
	});
});
