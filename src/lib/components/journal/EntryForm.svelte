<script lang="ts">
	import { onDestroy } from 'svelte';
	import { goto } from '$app/navigation';
	import { toast } from 'svelte-sonner';
	import { createQuery, useQueryClient } from '@tanstack/svelte-query';
	import { Input } from '$lib/components/ui/input';
	import { cn } from '$lib/utils';
	import NotesEditor from '$lib/notes/editor/NotesEditor.svelte';
	import EditorShell from '$lib/components/editor/EditorShell.svelte';
	import { createEntry, updateEntry, listByMonth } from '$lib/journal/entries';
	import { uploadJournalImage, uploadJournalFile, signedUrlFor } from '$lib/journal/media';
	import { withPathMedia } from '$lib/notes/media';
	import { createPlannerBridge } from '$lib/planner/bridge';
	import { todayIso, monthKey } from '$lib/finance/dates';
	import { MOODS, type JournalDoc, type JournalEntry } from '$lib/journal/types';
	import Download from '@lucide/svelte/icons/download';

	let { entry, date }: { entry?: JournalEntry; date?: string } = $props();

	const qc = useQueryClient();
	const planner = createPlannerBridge(qc);
	const entryId = entry?.id ?? crypto.randomUUID();

	/* svelte-ignore state_referenced_locally */
	let title = $state(entry?.title ?? '');
	/* svelte-ignore state_referenced_locally */
	let mood = $state<string | null>(entry?.mood ?? null);
	/* svelte-ignore state_referenced_locally */
	let occurredOn = $state(entry?.occurred_on ?? date ?? todayIso());
	/* svelte-ignore state_referenced_locally */
	let doc = $state<JournalDoc>(entry?.body_json ?? { type: 'doc', content: [] });

	/* svelte-ignore state_referenced_locally */
	let created = $state(!!entry);
	let touched = false;
	let saveState = $state<'idle' | 'saving' | 'saved'>('idle');
	let timer: ReturnType<typeof setTimeout> | undefined;

	const month = monthKey(occurredOn);
	const entriesList = createQuery(() => ({ queryKey: ['journal', month], queryFn: () => listByMonth(month) }));

	async function handleImage(file: File): Promise<string> {
		const path = await uploadJournalImage(file, entryId);
		return signedUrlFor(path);
	}
	async function handleFile(file: File) {
		const up = await uploadJournalFile(file, entryId);
		return { src: await signedUrlFor(up.path), name: up.name, size: up.size, mime: up.mime };
	}

	async function persist() {
		saveState = 'saving';
		try {
			const body_json = withPathMedia($state.snapshot(doc) as JournalDoc);
			if (created) {
				await updateEntry(entryId, { title, body_json, mood, occurred_on: occurredOn });
			} else {
				await createEntry({ id: entryId, title, body_json, mood, occurred_on: occurredOn });
				created = true;
			}
			qc.invalidateQueries({ queryKey: ['journal'] });
			qc.invalidateQueries({ queryKey: ['streak'] });
			saveState = 'saved';
		} catch {
			saveState = 'idle';
			toast.error('Could not save entry');
		}
	}

	function markDirty() {
		touched = true;
	}

	$effect(() => {
		void [title, mood, occurredOn, doc];
		if (!touched) return;
		saveState = 'saving';
		clearTimeout(timer);
		timer = setTimeout(persist, 700);
	});

	onDestroy(() => clearTimeout(timer));
</script>

<EditorShell
	entries={(entriesList.data ?? []).map((e) => ({
		id: e.id,
		href: `/journal/${e.id}`,
		title: e.title || 'Untitled',
		sub: e.occurred_on
	}))}
	listTitle="Journal"
	newHref="/journal/new"
	backHref="/journal"
	status={saveState === 'saving' ? 'Saving…' : saveState === 'saved' ? 'Saved' : ''}
>
	{#snippet actions(close)}
		<button class="menu-item" onclick={() => { window.print(); close(); }}>
			<Download class="size-4" /> Download PDF
		</button>
	{/snippet}

	{#snippet header()}
		<div class="no-print meta">
			<Input placeholder="Title" bind:value={title} oninput={markDirty} class="w-64" />
			<Input type="date" bind:value={occurredOn} oninput={markDirty} class="w-40" />
			<div class="flex gap-1">
				{#each MOODS as m}
					<button
						class={cn('rounded-full border px-3 py-1 text-xs capitalize', mood === m ? 'bg-secondary' : 'border-border')}
						onclick={() => {
							mood = mood === m ? null : m;
							markDirty();
						}}
					>
						{m}
					</button>
				{/each}
			</div>
		</div>
		<div class="print-only">
			<h1 style="font-size:1.9rem;font-weight:700;margin:0;">{title || 'Untitled'}</h1>
			<p style="color:#666;margin:.2rem 0 0;">{occurredOn}{mood ? ` · ${mood}` : ''}</p>
		</div>
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
				placeholder="Write about your day, or press “/” for blocks…"
		/>
	{/snippet}
</EditorShell>

<style>
	.meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem;
		margin-bottom: 1rem;
	}
</style>
