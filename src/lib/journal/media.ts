import { SupabaseStorageService } from '$lib/data/storage-service';
import { SupabaseRepository } from '$lib/data/repository';
import { compressImage } from '$lib/image';
import { mapImageSrcs, pathFromSrc } from './text';
import type { JournalDoc } from './types';

const storage = new SupabaseStorageService('media');

interface MediaAsset {
	id: string;
	owner_type: string;
	owner_id: string | null;
	storage_path: string;
	mime: string;
	size_bytes: number;
}
const mediaRepo = new SupabaseRepository<MediaAsset>('media_assets');

// Upload an image for a journal entry. Returns the storage path (stored in the doc).
export async function uploadJournalImage(file: File, entryId: string): Promise<string> {
	const small = await compressImage(file);
	const safe = small.name.replace(/[^a-zA-Z0-9._-]/g, '_');
	const path = `journal/${entryId}/${crypto.randomUUID()}-${safe}`;
	await storage.upload(small, path);
	await mediaRepo.create({
		owner_type: 'journal',
		owner_id: entryId,
		storage_path: path,
		mime: small.type,
		size_bytes: small.size
	} as Partial<MediaAsset>);
	return path;
}

// Upload a non-image file (PDF/etc.) for a journal entry. Returns path + metadata.
export async function uploadJournalFile(
	file: File,
	entryId: string
): Promise<{ path: string; name: string; size: number; mime: string }> {
	const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
	const path = `journal/${entryId}/${crypto.randomUUID()}-${safe}`;
	await storage.upload(file, path);
	await mediaRepo.create({
		owner_type: 'journal',
		owner_id: entryId,
		storage_path: path,
		mime: file.type,
		size_bytes: file.size
	} as Partial<MediaAsset>);
	return { path, name: file.name, size: file.size, mime: file.type };
}

// Sign a single storage path (week-long TTL).
export async function signedUrlFor(path: string): Promise<string> {
	return storage.signedUrl(path, 60 * 60 * 24 * 7);
}

// For display/editing: replace stored image paths with short-lived signed URLs.
export async function withSignedImages(doc: JournalDoc): Promise<JournalDoc> {
	const paths = new Set<string>();
	mapImageSrcs(doc, (src) => {
		paths.add(pathFromSrc(src));
		return src;
	});
	const signed = new Map<string, string>();
	for (const p of paths) {
		try {
			signed.set(p, await storage.signedUrl(p, 60 * 60 * 24 * 7));
		} catch {
			signed.set(p, p);
		}
	}
	return mapImageSrcs(doc, (src) => signed.get(pathFromSrc(src)) ?? src);
}

// For saving: collapse signed URLs back to bare storage paths.
export function withPathImages(doc: JournalDoc): JournalDoc {
	return mapImageSrcs(doc, (src) => pathFromSrc(src));
}
