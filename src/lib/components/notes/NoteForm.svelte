<script lang="ts">
	import { onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { toast } from 'svelte-sonner';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import NotesEditor from '$lib/notes/editor/NotesEditor.svelte';
	import EditorShell from '$lib/components/editor/EditorShell.svelte';
	import { createNote, updateNote, listNotes, type Note } from '$lib/notes/notes';
	import { uploadNoteImage, uploadNoteFile, withPathMedia } from '$lib/notes/media';
	import { signedUrlFor } from '$lib/journal/media';
	import { createPlannerBridge } from '$lib/planner/bridge';
	import type { JournalDoc } from '$lib/journal/types';
	import Pin from '@lucide/svelte/icons/pin';
	import Link2 from '@lucide/svelte/icons/link';
	import Download from '@lucide/svelte/icons/download';

	let { note }: { note?: Note } = $props();

	const qc = useQueryClient();
	const planner = createPlannerBridge(qc);
	const savedId = note?.id ?? crypto.randomUUID();

	/* svelte-ignore state_referenced_locally */
	let title = $state(note?.title ?? '');
	/* svelte-ignore state_referenced_locally */
	let pinned = $state(note?.pinned ?? false);
	/* svelte-ignore state_referenced_locally */
	let doc = $state<JournalDoc>(note?.body_json ?? { type: 'doc', content: [] });

	/* svelte-ignore state_referenced_locally */
	let created = $state(!!note);
	let touched = false;
	let saveState = $state<'idle' | 'saving' | 'saved'>('idle');
	let timer: ReturnType<typeof setTimeout> | undefined;

	const notesList = createQuery(() => ({ queryKey: ['notes'], queryFn: () => listNotes() }));

	async function handleImage(file: File): Promise<string> {
		const path = await uploadNoteImage(file, savedId);
		return signedUrlFor(path);
	}
	async function handleFile(file: File) {
		const up = await uploadNoteFile(file, savedId);
		return { src: await signedUrlFor(up.path), name: up.name, size: up.size, mime: up.mime };
	}

	async function persist() {
		saveState = 'saving';
		try {
			const body_json = withPathMedia($state.snapshot(doc) as JournalDoc);
			if (created) {
				await updateNote(savedId, { title, body_json, pinned });
			} else {
				await createNote({ id: savedId, title, body_json, pinned });
				created = true;
			}
			qc.invalidateQueries({ queryKey: ['notes'] });
			saveState = 'saved';
		} catch {
			saveState = 'idle';
			toast.error('Could not save note');
		}
	}

	function markDirty() {
		touched = true;
	}

	$effect(() => {
		void [title, pinned, doc];
		if (!touched) return;
		saveState = 'saving';
		clearTimeout(timer);
		timer = setTimeout(persist, 700);
	});

	onDestroy(() => clearTimeout(timer));

	function share() {
		navigator.clipboard?.writeText(`${location.origin}/notes/${savedId}`);
		toast.success('Link copied to clipboard');
	}
</script>

<EditorShell
	entries={(notesList.data ?? []).map((n) => ({
		id: n.id,
		href: `/notes/${n.id}`,
		title: `${n.pinned ? '📌 ' : ''}${n.title || 'Untitled'}`
	}))}
	listTitle="Notes"
	newHref="/notes/new"
	backHref="/notes"
	status={saveState === 'saving' ? 'Saving…' : saveState === 'saved' ? 'Saved' : ''}
>
	{#snippet actions(close)}
		<button class="menu-item" class:on={pinned} onclick={() => { pinned = !pinned; markDirty(); close(); }}>
			<Pin class="size-4" /> {pinned ? 'Unpin' : 'Pin'}
		</button>
		<button class="menu-item" onclick={() => { share(); close(); }}>
			<Link2 class="size-4" /> Copy link
		</button>
		<button class="menu-item" onclick={() => { window.print(); close(); }}>
			<Download class="size-4" /> Download PDF
		</button>
	{/snippet}

	{#snippet header()}
		<input class="title-input" placeholder="Untitled" bind:value={title} oninput={markDirty} />
	{/snippet}

	{#snippet children()}
		<NotesEditor
			content={doc}
			onUpdate={(d) => {
				doc = d;
				markDirty();
			}}
			onImageUpload={handleImage}
			onFileUpload={handleFile}
			{planner}
		/>
	{/snippet}
</EditorShell>

<style>
	.title-input {
		width: 100%;
		margin-bottom: 1rem;
		background: transparent;
		border: none;
		outline: none;
		font-size: 2.1rem;
		font-weight: 700;
		letter-spacing: -0.02em;
		color: var(--foreground);
		padding: 0;
	}
	.title-input::placeholder {
		color: color-mix(in oklch, var(--muted-foreground) 60%, transparent);
	}
</style>
