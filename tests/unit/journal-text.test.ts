import { describe, it, expect } from 'vitest';
import { extractText, pathFromSrc, mapImageSrcs, imagePaths } from '$lib/journal/text';

const doc = {
	type: 'doc',
	content: [
		{ type: 'paragraph', content: [{ type: 'text', text: 'Hello' }, { type: 'text', text: 'world' }] },
		{ type: 'image', attrs: { src: 'journal/e1/a.jpg' } },
		{ type: 'paragraph', content: [{ type: 'text', text: 'More.' }] }
	]
};

describe('extractText', () => {
	it('flattens text nodes', () => {
		expect(extractText(doc)).toBe('Hello world More.');
	});
	it('handles empty / non-object', () => {
		expect(extractText({})).toBe('');
		expect(extractText(null)).toBe('');
	});
});

describe('pathFromSrc', () => {
	it('extracts the storage path from a signed URL', () => {
		const url = 'http://127.0.0.1:54321/storage/v1/object/sign/media/journal/e1/a.jpg?token=xyz';
		expect(pathFromSrc(url)).toBe('journal/e1/a.jpg');
	});
	it('passes a bare path through', () => {
		expect(pathFromSrc('journal/e1/a.jpg')).toBe('journal/e1/a.jpg');
	});
});

describe('mapImageSrcs / imagePaths', () => {
	it('rewrites image srcs without mutating the input', () => {
		const out = mapImageSrcs(doc, () => 'SIGNED');
		expect((out.content as { type: string; attrs?: { src?: string } }[])[1].attrs?.src).toBe('SIGNED');
		// original untouched
		expect((doc.content[1] as { attrs: { src: string } }).attrs.src).toBe('journal/e1/a.jpg');
	});
	it('collects image paths', () => {
		expect(imagePaths(doc)).toEqual(['journal/e1/a.jpg']);
	});
});
