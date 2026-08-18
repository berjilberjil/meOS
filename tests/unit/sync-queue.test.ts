import { describe, it, expect, beforeEach, vi } from 'vitest';
import { localDb } from '$lib/data/db';
import { enqueue, pending, flush } from '$lib/data/sync-queue';

beforeEach(async () => {
	await localDb.mutations.clear();
});

describe('sync queue', () => {
	it('persists a mutation offline', async () => {
		await enqueue({
			table: 'transactions',
			op: 'create',
			payload: { data: { amount_paise: 1999 } },
			createdAt: 1
		});
		expect((await pending()).length).toBe(1);
	});

	it('flush replays mutations and clears the queue', async () => {
		await enqueue({
			table: 'transactions',
			op: 'create',
			payload: { data: { amount_paise: 10 } },
			createdAt: 1
		});
		const create = vi.fn().mockResolvedValue({ id: 'x' });
		const resolve = () => ({ create }) as never;
		const n = await flush(resolve);
		expect(n).toBe(1);
		expect(create).toHaveBeenCalledWith({ amount_paise: 10 });
		expect((await pending()).length).toBe(0);
	});
});
