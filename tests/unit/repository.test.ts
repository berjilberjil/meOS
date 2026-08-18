import { describe, it, expect, vi } from 'vitest';

const rows = [{ id: '1', name: 'x' }];
vi.mock('$lib/supabase/client', () => ({
	supabaseBrowser: () => ({
		from: () => ({
			select: () => Promise.resolve({ data: rows, error: null })
		})
	})
}));

describe('SupabaseRepository', () => {
	it('list() returns rows', async () => {
		const { SupabaseRepository } = await import('$lib/data/repository');
		const repo = new SupabaseRepository<{ id: string; name: string }>('thing');
		expect(await repo.list()).toEqual(rows);
	});
});
