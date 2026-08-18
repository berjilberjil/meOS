import Dexie, { type Table } from 'dexie';

export type Op = 'create' | 'update' | 'remove';

export interface Mutation {
	id?: number;
	table: string;
	op: Op;
	payload: { id?: string; data?: Record<string, unknown> };
	createdAt: number;
}

export class LocalDb extends Dexie {
	mutations!: Table<Mutation, number>;
	constructor() {
		super('myos');
		this.version(1).stores({ mutations: '++id, table, createdAt' });
	}
}

export const localDb = new LocalDb();
