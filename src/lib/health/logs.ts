import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import type { HealthLog, FitnessLog } from './types';

export const healthRepo = new SupabaseRepository<HealthLog>('health_logs');
export const fitnessRepo = new SupabaseRepository<FitnessLog>('fitness_logs');

function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export async function recentHealth(limit = 30): Promise<HealthLog[]> {
	const { data, error } = await db()
		.from('health_logs')
		.select('*')
		.order('logged_on', { ascending: false })
		.limit(limit);
	if (error) throw error;
	return (data ?? []) as HealthLog[];
}

// One health row per day: upsert on (user_id, logged_on).
export async function upsertHealth(loggedOn: string, patch: Partial<HealthLog>): Promise<void> {
	const { error } = await db()
		.from('health_logs')
		.upsert({ logged_on: loggedOn, ...patch }, { onConflict: 'user_id,logged_on' });
	if (error) throw error;
}

export async function recentFitness(limit = 30): Promise<FitnessLog[]> {
	const { data, error } = await db()
		.from('fitness_logs')
		.select('*')
		.order('logged_on', { ascending: false })
		.limit(limit);
	if (error) throw error;
	return (data ?? []) as FitnessLog[];
}

export async function addFitness(input: Partial<FitnessLog>): Promise<FitnessLog> {
	return fitnessRepo.create(input);
}

// Pure: total workout minutes within the last `days` ending at `today`.
export function totalDuration(logs: FitnessLog[], today: string, days: number): number {
	const cutoff = new Date(`${today}T00:00:00Z`);
	cutoff.setUTCDate(cutoff.getUTCDate() - (days - 1));
	const from = `${cutoff.getUTCFullYear()}-${String(cutoff.getUTCMonth() + 1).padStart(2, '0')}-${String(cutoff.getUTCDate()).padStart(2, '0')}`;
	return logs.filter((l) => l.logged_on >= from && l.logged_on <= today).reduce((s, l) => s + l.duration_min, 0);
}
