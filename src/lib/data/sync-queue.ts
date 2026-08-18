import { localDb, type Mutation } from './db';
import type { Repository } from './repository';

export async function enqueue(m: Mutation): Promise<void> {
	await localDb.mutations.add(m);
}

export async function pending(): Promise<Mutation[]> {
	return localDb.mutations.orderBy('createdAt').toArray();
}

export async function flush(resolve: (table: string) => Repository<unknown>): Promise<number> {
	const items = await pending();
	let synced = 0;
	for (const m of items) {
		const repo = resolve(m.table);
		if (m.op === 'create') await repo.create(m.payload.data ?? {});
		else if (m.op === 'update') await repo.update(m.payload.id!, m.payload.data ?? {});
		else if (m.op === 'remove') await repo.remove(m.payload.id!);
		await localDb.mutations.delete(m.id!);
		synced++;
	}
	return synced;
}
