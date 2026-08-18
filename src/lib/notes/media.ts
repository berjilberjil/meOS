import { SupabaseStorageService } from '$lib/data/storage-service';
import { SupabaseRepository } from '$lib/data/repository';
import { compressImage } from '$lib/image';
import { pathFromSrc } from '$lib/journal/text';
import type { JournalDoc } from '$lib/journal/types';

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

export interface UploadedFile {
	path: string;
	name: string;
	size: number;
	mime: string;
}

async function put(file: File, noteId: string): Promise<string> {
	const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_');
	const path = `note/${noteId}/${crypto.randomUUID()}-${safe}`;
	await storage.upload(file, path);
	await mediaRepo.create({
		owner_type: 'note',
		owner_id: noteId,
		storage_path: path,
		mime: file.type,
		size_bytes: file.size
	} as Partial<MediaAsset>);
	return path;
}

// Image upload returns the bare storage path (written into the image node src).
export async function uploadNoteImage(file: File, noteId: string): Promise<string> {
	return put(await compressImage(file), noteId);
}

// File (PDF/etc.) upload returns path + display metadata for the file block.
export async function uploadNoteFile(file: File, noteId: string): Promise<UploadedFile> {
	const path = await put(file, noteId);
	return { path, name: file.name, size: file.size, mime: file.type };
}

// Walk media-bearing nodes (image + file both keep their storage path in attrs.src).
function mapMediaSrcs(doc: JournalDoc, fn: (src: string) => string): JournalDoc {
	const clone = structuredClone(doc) as Record<string, unknown>;
	const walk = (n: unknown) => {
		if (!n || typeof n !== 'object') return;
		const node = n as { type?: string; attrs?: { src?: string }; content?: unknown[] };
		if (
			(node.type === 'image' || node.type === 'fileBlock') &&
			node.attrs &&
			typeof node.attrs.src === 'string'
		) {
			node.attrs.src = fn(node.attrs.src);
		}
		if (Array.isArray(node.content)) node.content.forEach(walk);
	};
	walk(clone);
	return clone;
}

// For display/editing: stored paths -> short-lived signed URLs.
export async function withSignedMedia(doc: JournalDoc): Promise<JournalDoc> {
	const paths = new Set<string>();
	mapMediaSrcs(doc, (src) => {
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
	return mapMediaSrcs(doc, (src) => signed.get(pathFromSrc(src)) ?? src);
}

// For saving: signed URLs -> bare storage paths.
export function withPathMedia(doc: JournalDoc): JournalDoc {
	return mapMediaSrcs(doc, (src) => pathFromSrc(src));
}
