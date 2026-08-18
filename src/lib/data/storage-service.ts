import { supabaseBrowser } from '$lib/supabase/client';

export interface StorageService {
	upload(file: File, path: string): Promise<{ path: string }>;
	signedUrl(path: string, ttlSeconds?: number): Promise<string>;
	remove(path: string): Promise<void>;
}

export class SupabaseStorageService implements StorageService {
	constructor(private bucket = 'media') {}
	private get s() {
		return supabaseBrowser().storage.from(this.bucket);
	}

	async upload(file: File, path: string) {
		const { error } = await this.s.upload(path, file, { upsert: false });
		if (error) throw error;
		return { path };
	}
	async signedUrl(path: string, ttlSeconds = 3600) {
		const { data, error } = await this.s.createSignedUrl(path, ttlSeconds);
		if (error) throw error;
		return data.signedUrl;
	}
	async remove(path: string) {
		const { error } = await this.s.remove([path]);
		if (error) throw error;
	}
}
