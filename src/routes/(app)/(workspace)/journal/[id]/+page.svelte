<script lang="ts">
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import EntryForm from '$lib/components/journal/EntryForm.svelte';
	import { entriesRepo } from '$lib/journal/entries';
	import { withSignedMedia } from '$lib/notes/media';
	import type { JournalEntry } from '$lib/journal/types';

	const id = $derived(page.params.id ?? '');

	const entry = createQuery(() => ({
		queryKey: ['journal', 'entry', id],
		queryFn: async (): Promise<JournalEntry | null> => {
			const e = await entriesRepo.get(id);
			if (!e) return null;
			return { ...e, body_json: await withSignedMedia(e.body_json) };
		}
	}));
</script>

<div class="h-full">
	{#if entry.data}
		{#key entry.data.id}
			<EntryForm entry={entry.data} />
		{/key}
	{:else if entry.isLoading}
		<p class="text-sm text-muted-foreground">Loading…</p>
	{:else}
		<p class="text-sm text-muted-foreground">Entry not found.</p>
	{/if}
</div>
