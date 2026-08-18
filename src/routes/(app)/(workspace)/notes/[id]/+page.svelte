<script lang="ts">
	import { page } from '$app/state';
	import { createQuery } from '@tanstack/svelte-query';
	import NoteForm from '$lib/components/notes/NoteForm.svelte';
	import { notesRepo } from '$lib/notes/notes';
	import { withSignedMedia } from '$lib/notes/media';

	const id = $derived(page.params.id ?? '');
	const note = createQuery(() => ({
		queryKey: ['notes', 'one', id],
		queryFn: async () => {
			const n = await notesRepo.get(id);
			if (n) n.body_json = await withSignedMedia(n.body_json);
			return n;
		}
	}));
</script>

<div class="h-full">
	{#if note.data}
		{#key note.data.id}
			<NoteForm note={note.data} />
		{/key}
	{:else if note.isLoading}
		<p class="text-sm text-muted-foreground">Loading…</p>
	{:else}
		<p class="text-sm text-muted-foreground">Note not found.</p>
	{/if}
</div>
