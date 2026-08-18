<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { Editor, wrappingInputRule } from '@tiptap/core';
	import StarterKit from '@tiptap/starter-kit';
	import { OrderedList } from '@tiptap/extension-list';
	import Image from '@tiptap/extension-image';
	import Placeholder from '@tiptap/extension-placeholder';
	import TaskList from '@tiptap/extension-task-list';
	import TaskItem from '@tiptap/extension-task-item';
	import { Details, DetailsSummary, DetailsContent } from '@tiptap/extension-details';
	import { BubbleMenu } from '@tiptap/extension-bubble-menu';
	import { DragHandle } from '@tiptap/extension-drag-handle';
	import { TextSelection } from '@tiptap/pm/state';
	import type { JournalDoc } from '$lib/journal/types';
	import { Callout, FileBlock, Bookmark } from './blocks';
	import { TodoChip, GoalChip } from './planner-nodes';
	import type { PlannerBridge } from '$lib/planner/bridge';
	import { SlashCommand } from './slash';
	import './editor.css';

	interface Props {
		content: JournalDoc;
		onUpdate: (doc: JournalDoc) => void;
		onImageUpload?: (file: File) => Promise<string>;
		onFileUpload?: (file: File) => Promise<{ src: string; name: string; size: number; mime: string }>;
		planner?: PlannerBridge;
		placeholder?: string;
	}
	let {
		content,
		onUpdate,
		onImageUpload,
		onFileUpload,
		planner,
		placeholder = 'Write something, or press "/" for blocks…'
	}: Props = $props();

	let element: HTMLDivElement;
	let bubbleEl: HTMLDivElement;
	let imageInput: HTMLInputElement;
	let fileInput: HTMLInputElement;
	let editor = $state<Editor>();
	let active = $state({ bold: false, italic: false, underline: false, strike: false, code: false, link: false });

	async function insertFiles(files: File[]) {
		if (!editor) return;
		for (const f of files) {
			if (f.type.startsWith('image/') && onImageUpload) {
				const src = await onImageUpload(f);
				editor.chain().focus().setImage({ src }).run();
			} else if (onFileUpload) {
				const up = await onFileUpload(f);
				editor.chain().focus().insertContent({ type: 'fileBlock', attrs: up }).run();
			}
		}
	}

	function refresh() {
		if (!editor) return;
		active = {
			bold: editor.isActive('bold'),
			italic: editor.isActive('italic'),
			underline: editor.isActive('underline'),
			strike: editor.isActive('strike'),
			code: editor.isActive('code'),
			link: editor.isActive('link')
		};
	}

	onMount(() => {
		editor = new Editor({
			element,
			extensions: [
				StarterKit.configure({ link: { openOnClick: false, autolink: true }, orderedList: false }),
				// Numbered lists always start at 1, regardless of the digit typed.
				OrderedList.extend({
					addInputRules() {
						return [wrappingInputRule({ find: /^(\d+)\.\s$/, type: this.type })];
					}
				}),
				Image,
				TaskList,
				TaskItem.configure({ nested: true }),
				Details.configure({ persist: true }),
				DetailsSummary,
				DetailsContent,
				Callout,
				FileBlock,
				Bookmark,
				TodoChip,
				GoalChip,
				SlashCommand,
				BubbleMenu.configure({
					element: bubbleEl,
					shouldShow: ({ editor: e, from, to }) =>
						e.isFocused && from !== to && e.isEditable && !e.isActive('codeBlock')
				}),
				DragHandle.configure({
					render: () => {
						const el = document.createElement('div');
						el.className = 'drag-handle';
						el.innerHTML =
							'<svg viewBox="0 0 16 16" width="14" height="14"><g fill="currentColor"><circle cx="5" cy="3" r="1.4"/><circle cx="11" cy="3" r="1.4"/><circle cx="5" cy="8" r="1.4"/><circle cx="11" cy="8" r="1.4"/><circle cx="5" cy="13" r="1.4"/><circle cx="11" cy="13" r="1.4"/></g></svg>';
						return el;
					}
				}),
				Placeholder.configure({ placeholder, includeChildren: true })
			],
			content: content && Object.keys(content).length ? content : undefined,
			editorProps: {
				handlePaste: (_view, event) => {
					const files = Array.from(event.clipboardData?.files ?? []).filter(
						(f) => f.type.startsWith('image/') || onFileUpload
					);
					if (!files.length) return false;
					event.preventDefault();
					insertFiles(files);
					return true;
				},
				handleDrop: (view, event, _slice, moved) => {
					if (moved) return false;
					const files = Array.from(event.dataTransfer?.files ?? []);
					if (!files.length) return false;
					event.preventDefault();
					const coords = view.posAtCoords({ left: event.clientX, top: event.clientY });
					if (coords) {
						view.dispatch(
							view.state.tr.setSelection(TextSelection.near(view.state.doc.resolve(coords.pos)))
						);
					}
					insertFiles(files);
					return true;
				}
			},
			onUpdate: ({ editor }) => onUpdate(editor.getJSON() as JournalDoc),
			onSelectionUpdate: refresh,
			onTransaction: refresh
		});
		(editor.storage as unknown as Record<string, unknown>).notesPick = {
			image: () => imageInput?.click(),
			file: () => fileInput?.click()
		};
		(editor.storage as unknown as Record<string, unknown>).planner = planner;
	});

	onDestroy(() => editor?.destroy());

	async function onImagePick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file || !onImageUpload || !editor) return;
		const src = await onImageUpload(file);
		editor.chain().focus().setImage({ src }).run();
	}
	async function onFilePick(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		input.value = '';
		if (!file || !onFileUpload || !editor) return;
		const { src, name, size, mime } = await onFileUpload(file);
		editor.chain().focus().insertContent({ type: 'fileBlock', attrs: { src, name, size, mime } }).run();
	}

	function toggleLink() {
		if (!editor) return;
		if (editor.isActive('link')) {
			editor.chain().focus().unsetLink().run();
			return;
		}
		const url = window.prompt('Link URL');
		if (url) editor.chain().focus().setLink({ href: url }).run();
	}
</script>

<div class="notes-editor">
	<div bind:this={element}></div>

	<div bind:this={bubbleEl} class="bubble-menu">
		{#if editor}
			<button class="bm-btn" class:on={active.bold} onmousedown={(e) => { e.preventDefault(); editor!.chain().focus().toggleBold().run(); }}>B</button>
			<button class="bm-btn it" class:on={active.italic} onmousedown={(e) => { e.preventDefault(); editor!.chain().focus().toggleItalic().run(); }}>i</button>
			<button class="bm-btn un" class:on={active.underline} onmousedown={(e) => { e.preventDefault(); editor!.chain().focus().toggleUnderline().run(); }}>U</button>
			<button class="bm-btn st" class:on={active.strike} onmousedown={(e) => { e.preventDefault(); editor!.chain().focus().toggleStrike().run(); }}>S</button>
			<button class="bm-btn mono" class:on={active.code} onmousedown={(e) => { e.preventDefault(); editor!.chain().focus().toggleCode().run(); }}>{'</>'}</button>
			<button class="bm-btn" class:on={active.link} onmousedown={(e) => { e.preventDefault(); toggleLink(); }}>🔗</button>
		{/if}
	</div>

	<input bind:this={imageInput} type="file" accept="image/*" class="hidden" onchange={onImagePick} />
	<input bind:this={fileInput} type="file" accept="application/pdf,image/*,.doc,.docx,.txt,.zip,.csv,.xlsx" class="hidden" onchange={onFilePick} />
</div>
