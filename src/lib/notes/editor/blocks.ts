import { Node, mergeAttributes } from '@tiptap/core';

export function humanSize(bytes: number): string {
	if (!bytes) return '';
	const u = ['B', 'KB', 'MB', 'GB'];
	let n = bytes;
	let i = 0;
	while (n >= 1024 && i < u.length - 1) {
		n /= 1024;
		i++;
	}
	return `${n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)} ${u[i]}`;
}

export function domainOf(url: string): string {
	try {
		return new URL(url).hostname.replace(/^www\./, '');
	} catch {
		return url;
	}
}

export function faviconOf(url: string): string {
	const d = domainOf(url);
	return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(d)}&sz=64`;
}

// A coloured callout block that holds editable block content.
export const Callout = Node.create({
	name: 'callout',
	group: 'block',
	content: 'block+',
	defining: true,
	addAttributes() {
		return { emoji: { default: '💡' } };
	},
	parseHTML() {
		return [{ tag: 'div[data-callout]' }];
	},
	renderHTML({ node, HTMLAttributes }) {
		return [
			'div',
			mergeAttributes(HTMLAttributes, { 'data-callout': '', class: 'callout' }),
			['span', { class: 'callout-emoji', contenteditable: 'false' }, node.attrs.emoji || '💡'],
			['div', { class: 'callout-body' }, 0]
		];
	}
});

// A file card (PDF / any upload). Storage path lives in `src`, signed at display.
export const FileBlock = Node.create({
	name: 'fileBlock',
	group: 'block',
	atom: true,
	draggable: true,
	selectable: true,
	addAttributes() {
		return {
			src: { default: '' },
			name: { default: 'file' },
			size: { default: 0 },
			mime: { default: '' }
		};
	},
	parseHTML() {
		return [{ tag: 'a[data-file]' }];
	},
	renderHTML({ node }) {
		const { src, name, size } = node.attrs as { src: string; name: string; size: number };
		return [
			'a',
			{
				'data-file': '',
				href: src,
				target: '_blank',
				rel: 'noopener noreferrer',
				class: 'file-block',
				contenteditable: 'false'
			},
			['span', { class: 'file-ic' }, '📄'],
			[
				'span',
				{ class: 'file-meta' },
				['span', { class: 'file-name' }, name],
				['span', { class: 'file-size' }, humanSize(size)]
			]
		];
	}
});

// A bookmark / link-preview card. Phase 1 shows domain + favicon; phase 2 enriches.
export const Bookmark = Node.create({
	name: 'bookmark',
	group: 'block',
	atom: true,
	draggable: true,
	selectable: true,
	addAttributes() {
		return {
			href: { default: '' },
			title: { default: '' },
			description: { default: '' },
			image: { default: '' },
			favicon: { default: '' },
			domain: { default: '' }
		};
	},
	parseHTML() {
		return [{ tag: 'a[data-bookmark]' }];
	},
	renderHTML({ node }) {
		const a = node.attrs as {
			href: string;
			title: string;
			description: string;
			image: string;
			favicon: string;
			domain: string;
		};
		const text = [
			'div',
			{ class: 'bm-text' },
			['div', { class: 'bm-title' }, a.title || a.domain || a.href],
			['div', { class: 'bm-desc' }, a.description || ''],
			[
				'div',
				{ class: 'bm-url' },
				['img', { class: 'bm-fav', src: a.favicon || faviconOf(a.href), alt: '' }],
				['span', {}, a.domain || domainOf(a.href)]
			]
		];
		const children: unknown[] = [text];
		if (a.image) children.push(['div', { class: 'bm-img' }, ['img', { src: a.image, alt: '' }]]);
		return [
			'a',
			{
				'data-bookmark': '',
				href: a.href,
				target: '_blank',
				rel: 'noopener noreferrer',
				class: 'bookmark',
				contenteditable: 'false'
			},
			...children
		];
	}
});
