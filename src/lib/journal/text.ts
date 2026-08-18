import type { JournalDoc } from './types';

// Flatten a TipTap document's text nodes into a single searchable string.
export function extractText(doc: unknown): string {
	const parts: string[] = [];
	const walk = (n: unknown) => {
		if (!n || typeof n !== 'object') return;
		const node = n as { text?: string; content?: unknown[] };
		if (typeof node.text === 'string') parts.push(node.text);
		if (Array.isArray(node.content)) node.content.forEach(walk);
	};
	walk(doc);
	return parts.join(' ').replace(/\s+/g, ' ').trim();
}

const SIGN_RE = /\/object\/sign\/media\/(.+?)(?:\?|$)/;

// Storage path <- a Supabase signed URL (or pass through if already a path).
export function pathFromSrc(src: string): string {
	const m = src.match(SIGN_RE);
	if (m) return decodeURIComponent(m[1]);
	return src;
}

// Walk image nodes and apply a transform to each `src` attribute, returning a new doc.
export function mapImageSrcs(doc: JournalDoc, fn: (src: string) => string): JournalDoc {
	const clone = structuredClone(doc) as Record<string, unknown>;
	const walk = (n: unknown) => {
		if (!n || typeof n !== 'object') return;
		const node = n as { type?: string; attrs?: { src?: string }; content?: unknown[] };
		if (node.type === 'image' && node.attrs && typeof node.attrs.src === 'string') {
			node.attrs.src = fn(node.attrs.src);
		}
		if (Array.isArray(node.content)) node.content.forEach(walk);
	};
	walk(clone);
	return clone;
}

// Collect all image storage paths referenced by a doc.
export function imagePaths(doc: JournalDoc): string[] {
	const paths: string[] = [];
	mapImageSrcs(doc, (src) => {
		paths.push(pathFromSrc(src));
		return src;
	});
	return paths;
}
