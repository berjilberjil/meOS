import { SupabaseStorageService } from '$lib/data/storage-service';
import { supabaseBrowser } from '$lib/supabase/client';
import { compressImage } from '$lib/image';

const storage = new SupabaseStorageService('media');

export interface ProgressPhoto {
	id: string;
	path: string;
	url: string;
	created_at: string;
}

export async function uploadFitnessPhoto(file: File): Promise<void> {
	const small = await compressImage(file);
	const safe = small.name.replace(/[^a-zA-Z0-9._-]/g, '_');
	const path = `fitness/photos/${crypto.randomUUID()}-${safe}`;
	await storage.upload(small, path);
	const { error } = await supabaseBrowser()
		.from('media_assets')
		.insert({ owner_type: 'fitness_photo', storage_path: path, mime: small.type, size_bytes: small.size });
	if (error) throw error;
}

export async function listFitnessPhotos(limit = 24): Promise<ProgressPhoto[]> {
	const { data } = await supabaseBrowser()
		.from('media_assets')
		.select('id, storage_path, created_at')
		.eq('owner_type', 'fitness_photo')
		.order('created_at', { ascending: false })
		.limit(limit);
	const out: ProgressPhoto[] = [];
	for (const r of (data ?? []) as { id: string; storage_path: string; created_at: string }[]) {
		try {
			out.push({
				id: r.id,
				path: r.storage_path,
				url: await storage.signedUrl(r.storage_path, 60 * 60 * 24 * 7),
				created_at: r.created_at
			});
		} catch {
			/* skip unsignable */
		}
	}
	return out;
}

export async function deleteFitnessPhoto(id: string, path: string): Promise<void> {
	await supabaseBrowser().from('media_assets').delete().eq('id', id);
	try {
		await storage.remove(path);
	} catch {
		/* storage cleanup best-effort */
	}
}
