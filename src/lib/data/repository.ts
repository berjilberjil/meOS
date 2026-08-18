import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';

export interface Repository<T> {
	list(): Promise<T[]>;
	get(id: string): Promise<T | null>;
	create(input: Partial<T>): Promise<T>;
	update(id: string, patch: Partial<T>): Promise<T>;
	remove(id: string): Promise<void>;
}

export class SupabaseRepository<T extends { id: string }> implements Repository<T> {
	constructor(private table: string) {}

	// A generic repository keyed by a dynamic table name can't be inferred against
	// the strongly-typed client, so we access it as an untyped client internally.
	// The public Repository<T> surface stays fully typed.
	private get db(): SupabaseClient {
		return supabaseBrowser() as unknown as SupabaseClient;
	}

	async list(): Promise<T[]> {
		const { data, error } = await this.db.from(this.table).select('*');
		if (error) throw error;
		return (data ?? []) as T[];
	}
	async get(id: string): Promise<T | null> {
		const { data, error } = await this.db.from(this.table).select('*').eq('id', id).maybeSingle();
		if (error) throw error;
		return (data ?? null) as T | null;
	}
	async create(input: Partial<T>): Promise<T> {
		const row = input as Record<string, unknown>;
		const { data, error } = await this.db.from(this.table).insert(row).select().single();
		if (error) throw error;
		return data as T;
	}
	async update(id: string, patch: Partial<T>): Promise<T> {
		const row = patch as Record<string, unknown>;
		const { data, error } = await this.db
			.from(this.table)
			.update(row)
			.eq('id', id)
			.select()
			.single();
		if (error) throw error;
		return data as T;
	}
	async remove(id: string): Promise<void> {
		const { error } = await this.db.from(this.table).delete().eq('id', id);
		if (error) throw error;
	}
}
