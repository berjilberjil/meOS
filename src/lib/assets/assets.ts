import type { SupabaseClient } from '@supabase/supabase-js';
import { supabaseBrowser } from '$lib/supabase/client';
import { SupabaseRepository } from '$lib/data/repository';
import type { Asset, AssetSettings } from './types';

export const assetsRepo = new SupabaseRepository<Asset>('assets');

// The 0011 tables aren't in the generated Database types, so — like
// SupabaseRepository does for dynamic tables — reach them via an untyped client.
function db(): SupabaseClient {
	return supabaseBrowser() as unknown as SupabaseClient;
}

export function listAssets(): Promise<Asset[]> {
	return assetsRepo.list();
}
export function createAsset(input: Partial<Asset>): Promise<Asset> {
	return assetsRepo.create(input);
}
export function updateAsset(id: string, patch: Partial<Asset>): Promise<Asset> {
	return assetsRepo.update(id, patch);
}
export function removeAsset(id: string): Promise<void> {
	return assetsRepo.remove(id);
}

export const DEFAULT_SETTINGS: AssetSettings = {
	income_amount_paise: 0,
	income_period: 'monthly',
	global_target_cpd_paise: 1000 // ₹10/day
};

// One settings row per owner (RLS-scoped). Read falls back to defaults so the
// page works before the row exists; save creates-or-updates that single row.
export async function getAssetSettings(): Promise<AssetSettings> {
	const { data } = await db()
		.from('asset_settings')
		.select('income_amount_paise, income_period, global_target_cpd_paise')
		.maybeSingle();
	return (data as AssetSettings | null) ?? DEFAULT_SETTINGS;
}

export async function saveAssetSettings(s: AssetSettings): Promise<void> {
	const client = db();
	const { data } = await client.from('asset_settings').select('user_id').maybeSingle();
	if (data) {
		const { error } = await client
			.from('asset_settings')
			.update(s)
			.eq('user_id', (data as { user_id: string }).user_id);
		if (error) throw error;
	} else {
		const { error } = await client.from('asset_settings').insert(s);
		if (error) throw error;
	}
}
